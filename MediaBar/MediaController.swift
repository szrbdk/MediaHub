import AppKit
import OSLog

final class MediaController {
    let view = TouchBarView()
    private let client = MediaClient()
    private let music = MusicAutomation()
    private lazy var presenter = TouchBarPresenter(view: view)
    private var state = MediaState()
    private var favoriteRequest = FavoriteRequestState()
    private var seekRequest = SeekRequestState()
    private var seekGeneration = 0
    private var favoriteReadBusy = false
    private var favoriteWriteRevision: Int?
    private var pollTimer: Timer?
    private var favoriteTimer: Timer?
    private var progressTimer: Timer?
    private var holdTimer: Timer?
    private var seekingEndCommand: Int?
    private var readBusy = false
    private var retryCount = 0
    private var retryAfter = Date.distantPast
    private var stopped = true
    private var revision = 0
    private let logger = Logger(subsystem: "com.sezerbudak.MediaBar", category: "Controller")

    func start() {
        stopped = false
        view.onAction = { [weak self] in self?.handle($0) }
        presenter.onContextChange = { [weak self] in self?.endSeeking() }
        presenter.start()
        pollTimer = timer(interval: 0.5) { [weak self] in self?.readState() }
        progressTimer = timer(interval: 0.5) { [weak self] in self?.view.refreshProgress() }
        favoriteTimer = timer(interval: 5) { [weak self] in self?.readFavorite() }
        readState()
    }

    private func timer(interval: Double, action: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in action() }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func readState() {
        guard !stopped, !readBusy, Date() >= retryAfter else { return }
        readBusy = true
        let observedSeekGeneration = seekGeneration
        client.read { [weak self] payload in
            guard let self, !self.stopped else { return }
            self.readBusy = false
            // A snapshot requested before the latest seek can arrive after its
            // command reply. Discard it before it can acknowledge the new target.
            guard observedSeekGeneration == self.seekGeneration else { return }
            if payload == nil {
                self.retryCount = min(10, self.retryCount + 1)
                self.retryAfter = Date().addingTimeInterval(Double(self.retryCount * 3))
            } else {
                self.retryCount = 0
                self.retryAfter = .distantPast
            }
            var next = payload.map { MediaState(payload: $0) } ?? MediaState()
            let changed = next.trackKey != self.state.trackKey
            if changed || !next.hasMedia || !next.timeline.isValid { self.endSeeking() }
            if changed {
                self.seekRequest.reset()
                self.revision += 1
                self.music.cancelPendingRequests()
                self.favoriteWriteRevision = nil
                self.favoriteRequest.changeTrack(to: next.trackKey)
            } else {
                next.favorite = self.state.favorite
                next.favoritePending = self.favoriteRequest.isPending
            }
            next.timeline = self.seekRequest.receive(next.timeline, now: Date().timeIntervalSince1970)
            next.seekPending = self.seekRequest.isPending
            self.state = next
            self.view.render(next)
            if changed { self.readFavorite() }
        }
    }

    private func handle(_ action: MediaAction) {
        guard !stopped else { return }
        if case .endSeeking = action { endSeeking(); return }
        guard state.hasMedia else { return }
        switch action {
        case .togglePlayback: send(2)
        case .previous: send(state.isPodcast ? 12 : 5)
        case .next: send(state.isPodcast ? 13 : 4)
        case .beginSeeking(let forward):
            endSeeking()
            seekingEndCommand = forward ? 9 : 11
            send(forward ? 8 : 10)
            holdTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.endSeeking() }
        case .endSeeking: break
        case .seek(let fraction, let key):
            guard key == state.trackKey, let micros = state.timeline.seekMicroseconds(fraction: fraction) else { return }
            let expectedRevision = revision
            let seconds = Double(micros) / 1_000_000
            seekGeneration += 1
            let request = seekRequest.begin(position: seconds, timeline: state.timeline, now: Date().timeIntervalSince1970)
            state.timeline = seekRequest.displayedTimeline(fallback: state.timeline)
            state.seekPending = true
            view.render(state)
            client.seek(seconds: seconds) { [weak self] success in
                guard let self, !self.stopped, self.revision == expectedRevision,
                      self.seekRequest.requestID == request else { return }
                if let fallback = self.seekRequest.complete(request, success: success) {
                    self.state.timeline = fallback
                }
                self.state.seekPending = self.seekRequest.isPending
                if !success { self.logger.error("Seek command failed") }
                self.view.render(self.state)
            }
        case .openPlayer:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: state.bundleIdentifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error { self?.logger.error("Player activation failed: \(error.localizedDescription, privacy: .public)") }
            }
        case .addFavorite: addFavorite()
        }
    }

    private func send(_ command: Int) {
        client.send(command) { [weak self] success in
            if !success { self?.logger.error("Media command \(command) failed") }
        }
    }

    private func endSeeking(completion: @escaping () -> Void = {}) {
        holdTimer?.invalidate()
        holdTimer = nil
        guard let command = seekingEndCommand else { completion(); return }
        seekingEndCommand = nil
        client.send(command) { [weak self] success in
            if !success { self?.logger.error("End-seek command failed") }
            completion()
        }
    }

    private func readFavorite() {
        guard !stopped, state.hasMedia, state.isMusic, !favoriteReadBusy,
              favoriteWriteRevision != revision else { return }
        favoriteReadBusy = true
        let key = state.trackKey
        let expectedRevision = revision
        let observedRequest = favoriteRequest.requestID
        music.favorite(forTitle: state.title, artist: state.artist, add: false) { [weak self] favorite, error in
            guard let self else { return }
            self.favoriteReadBusy = false
            guard !self.stopped else { return }
            guard self.revision == expectedRevision else { self.readFavorite(); return }
            // A read started before a tap must not resolve that newer request.
            guard self.favoriteRequest.resolveRead(for: key, observedRequestID: observedRequest,
                confirmed: favorite?.boolValue == true, failed: error != nil || favorite == nil) else { return }
            if let favorite { self.state.favorite = favorite.boolValue }
            self.state.favoritePending = self.favoriteRequest.isPending
            if let error { self.logger.error("Favorite read failed: \(error, privacy: .public)") }
            self.view.render(self.state)
        }
    }

    private func addFavorite() {
        guard state.isMusic, !state.favorite, let request = favoriteRequest.begin() else { return }
        let expectedRevision = revision
        favoriteWriteRevision = revision
        state.favoritePending = true
        view.render(state)
        music.favorite(forTitle: state.title, artist: state.artist, add: true) { [weak self] favorite, error in
            guard let self, !self.stopped, self.revision == expectedRevision else { return }
            self.favoriteWriteRevision = nil
            let waiting = error == nil && favorite?.boolValue == false
            self.favoriteRequest.finish(request, stillWaiting: waiting)
            if let favorite { self.state.favorite = favorite.boolValue }
            self.state.favoritePending = self.favoriteRequest.isPending
            if let error { self.logger.error("Favorite update failed: \(error, privacy: .public)") }
            self.view.render(self.state)
            self.readFavorite()
        }
    }

    func stop(completion: @escaping () -> Void) {
        stopped = true
        revision += 1
        seekRequest.reset()
        music.cancelPendingRequests()
        [pollTimer, progressTimer, favoriteTimer].forEach { $0?.invalidate() }
        presenter.stop()
        view.stop()
        endSeeking { [self] in client.stop(completion: completion) }
    }
}
