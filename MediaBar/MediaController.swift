import AppKit
import OSLog

final class MediaController {
    let view = TouchBarView()
    private let client = MediaClient()
    private let music = MusicAutomation()
    private let preferences = FeaturePreferences()
    private let blacklist = BlacklistStore()
    private var autoSkip = AutoSkipState()
    private var blacklistOperationError: String?
    private var autoSkipError: String?
    var notificationsEnabled: Bool { preferences.isEnabled(.notifications) }
    var touchBarEnabled: Bool { preferences.isEnabled(.touchBar) }
    var autoSkipEnabled: Bool { preferences.isEnabled(.autoSkip) }
    var currentMediaState: MediaState { state }
    var blacklistDocument: BlacklistDocument { blacklist.document }
    var canEditBlacklist: Bool { blacklist.readError == nil }
    var blacklistStatus: String? {
        blacklist.readError ?? blacklistOperationError ?? autoSkipError
            ?? (autoSkip.limitReached ? L("error.skip_limit") : nil)
    }
    private let trackNotifications = TrackNotificationPresenter()
    private var trackAnnouncements = TrackAnnouncementState()
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
        presenter.setEnabled(touchBarEnabled)
        presenter.start()
        trackNotifications.setEnabled(notificationsEnabled)
        trackNotifications.start()
        pollTimer = timer(interval: 0.5) { [weak self] in self?.readState() }
        progressTimer = timer(interval: 0.5) { [weak self] in self?.view.refreshProgress() }
        favoriteTimer = timer(interval: 5) { [weak self] in self?.readFavorite() }
        readState()
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        preferences.setEnabled(enabled, for: .notifications)
        trackNotifications.setEnabled(enabled)
    }

    func setTouchBarEnabled(_ enabled: Bool) {
        preferences.setEnabled(enabled, for: .touchBar)
        presenter.setEnabled(enabled)
        if enabled { readFavorite() }
    }

    func setAutoSkipEnabled(_ enabled: Bool) {
        preferences.setEnabled(enabled, for: .autoSkip)
        autoSkip.resetLimit()
        autoSkip.ignoreCurrent(state)
        autoSkipError = nil
    }

    func reloadBlacklist() {
        blacklist.reload()
        renderState()
    }

    func refreshLanguage() {
        blacklist.reload()
        // Errors describe an earlier action; do not retain them in the previous language.
        blacklistOperationError = nil
        if autoSkipError != nil { autoSkipError = L("error.skip_failed") }
        renderState()
    }

    func changeBlacklist(_ entry: BlacklistEntry, adding: Bool) {
        do {
            blacklist.reload()
            if adding { try blacklist.add(entry) }
            else { try blacklist.remove(entry) }
            blacklistOperationError = nil
            // Editing the list never re-evaluates or skips the currently playing song.
            autoSkip.ignoreCurrent(state)
        } catch {
            blacklistOperationError = L("error.blacklist_save")
            logger.error("Blacklist write failed: \(error.localizedDescription, privacy: .public)")
        }
        renderState()
    }

    private func renderState() {
        state.canEditBlacklist = canEditBlacklist
        state.songBlacklisted = state.songBlacklistEntry.map { blacklist.document.contains($0) } ?? false
        state.primaryArtistBlacklisted = state.primaryArtistBlacklistEntry.map { blacklist.document.contains($0) } ?? false
        view.render(state)
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
            self.renderState()
            if payload != nil {
                let decision = self.autoSkip.observe(next, blacklist: self.blacklist.document,
                    enabled: self.autoSkipEnabled && self.blacklist.readError == nil, now: Date().timeIntervalSince1970)
                if decision == .skip {
                    self.endSeeking()
                    self.trackNotifications.cancelCurrent()
                    self.autoSkipError = nil
                    let expectedRevision = self.revision
                    self.client.send(4) { [weak self] success in
                        guard let self, !self.stopped, self.revision == expectedRevision else { return }
                        if success { self.readState() }
                        else {
                            self.autoSkipError = L("error.skip_failed")
                            self.logger.error("Automatic skip command failed")
                        }
                    }
                }
                if let announcement = self.trackAnnouncements.observe(next, enabled: self.notificationsEnabled && decision != .skip) {
                    self.trackNotifications.show(announcement)
                } else {
                    self.trackNotifications.updateContent(for: next)
                }
            }
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
            renderState()
            client.seek(seconds: seconds) { [weak self] success in
                guard let self, !self.stopped, self.revision == expectedRevision,
                      self.seekRequest.requestID == request else { return }
                if let fallback = self.seekRequest.complete(request, success: success) {
                    self.state.timeline = fallback
                }
                self.state.seekPending = self.seekRequest.isPending
                if !success { self.logger.error("Seek command failed") }
                self.renderState()
            }
        case .toggleBlacklist(let entry, let key):
            guard key == state.trackKey, canEditBlacklist,
                  entry == state.songBlacklistEntry || entry == state.primaryArtistBlacklistEntry else { return }
            changeBlacklist(entry, adding: !blacklist.document.contains(entry))
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
        guard !stopped, touchBarEnabled, state.hasMedia, state.isMusic, !favoriteReadBusy,
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
            self.renderState()
        }
    }

    private func addFavorite() {
        guard state.isMusic, !state.favorite, let request = favoriteRequest.begin() else { return }
        let expectedRevision = revision
        favoriteWriteRevision = revision
        state.favoritePending = true
        renderState()
        music.favorite(forTitle: state.title, artist: state.artist, add: true) { [weak self] favorite, error in
            guard let self, !self.stopped, self.revision == expectedRevision else { return }
            self.favoriteWriteRevision = nil
            let waiting = error == nil && favorite?.boolValue == false
            self.favoriteRequest.finish(request, stillWaiting: waiting)
            if let favorite { self.state.favorite = favorite.boolValue }
            self.state.favoritePending = self.favoriteRequest.isPending
            if let error { self.logger.error("Favorite update failed: \(error, privacy: .public)") }
            self.renderState()
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
        trackNotifications.stop()
        view.stop()
        endSeeking { [self] in client.stop(completion: completion) }
    }
}
