import AppKit

/// An app-owned overlay; never activates MediaHub or requests notification access.
final class TrackNotificationPresenter {
    private var panel: TrackNotificationPanel?
    private let content = MiniPlayerView(frame: .zero)
    private var transition = MiniPlayerTransition()
    private var animationTimer: Timer?
    private var environmentTimer: Timer?
    private var dismissing = false
    private var pendingShow: DispatchWorkItem?
    private var pendingDismiss: DispatchWorkItem?
    private var generation = 0
    private var sessionSuspended = false
    private var screenLocked = false
    private var suspended: Bool { sessionSuspended || screenLocked }
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var currentAnnouncement: TrackAnnouncement?
    private var enabled = true
    private var position: NotificationPosition = .topCenter

    func setPosition(_ position: NotificationPosition) {
        guard self.position != position else { return }
        dismiss(animated: false)
        self.position = position
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled { dismiss(animated: false) }
    }

    func cancelCurrent() { dismiss(animated: false) }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sessionSuspended = true
                self?.dismiss(animated: false)
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sessionSuspended = false
            })
        }
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    self?.screenLocked = locked
                    if locked { self?.dismiss(animated: false) }
                })
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.dismiss(animated: false)
            }
    }

    func show(_ announcement: TrackAnnouncement) {
        guard enabled, !suspended else { return }
        currentAnnouncement = announcement
        generation += 1
        let expectedGeneration = generation
        pendingShow?.cancel()
        pendingDismiss?.cancel()
        // Replace bursts of track changes rather than queuing obsolete banners.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, self.generation == expectedGeneration, !self.suspended,
                  let latest = self.currentAnnouncement else { return }
            self.present(latest)
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func updateContent(for state: MediaState) {
        guard enabled else { return }
        let updated = TrackAnnouncement(state: state)
        guard let currentAnnouncement, updated.hasSameTrack(as: currentAnnouncement),
              updated != currentAnnouncement else { return }
        self.currentAnnouncement = updated
        // Artwork can arrive after the song metadata. Update the visible card
        // without replaying its animation or extending its dismissal deadline.
        if panel?.isVisible == true { content.render(updated) }
    }

    private func present(_ announcement: TrackAnnouncement) {
        guard enabled, !suspended else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let placement = placement(on: screen)
        let visibleFrame = placement.frame
        let window: TrackNotificationPanel
        if let panel { window = panel }
        else {
            window = TrackNotificationPanel(contentRect: visibleFrame, styleMask: [.borderless, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary,
                                         .stationary, .ignoresCycle]
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = content
            panel = window
        }
        if let previousScreen = window.screen, previousScreen != screen {
            window.orderOut(nil)
            transition.move(to: .hidden, at: ProcessInfo.processInfo.systemUptime, animated: false)
        }
        window.setFrame(visibleFrame, display: false)
        content.setPosition(position)
        content.setDetached(placement.detached)
        content.setForm(.announcement)
        content.render(announcement)
        content.setPresented(true)
        dismissing = false
        transition.move(to: .announcement, at: ProcessInfo.processInfo.systemUptime,
                        animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        window.orderFrontRegardless()
        animate()
        environmentTimer?.invalidate()
        let environmentTimer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.refreshPlacement() }
        environmentTimer.tolerance = 0.03
        RunLoop.main.add(environmentTimer, forMode: .common)
        self.environmentTimer = environmentTimer
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            self.dismiss(animated: true)
        }
        pendingDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.26, execute: work)
    }

    private func dismiss(animated: Bool) {
        generation += 1
        pendingShow?.cancel()
        pendingDismiss?.cancel()
        currentAnnouncement = nil
        environmentTimer?.invalidate()
        environmentTimer = nil
        dismissing = true
        transition.move(to: .hidden, at: ProcessInfo.processInfo.systemUptime,
                        animated: animated && panel?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        animate()
    }

    private func placement(on screen: NSScreen) -> (frame: NSRect, detached: Bool) {
        let detached = position.isTop && NSMenu.menuBarVisible()
        let barHeight = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
        return (position.frame(in: screen.frame, safeTop: screen.safeAreaInsets.top,
                               detached: detached, menuBarHeight: barHeight), detached)
    }

    private func refreshPlacement() {
        guard !dismissing, let panel, panel.isVisible, let screen = panel.screen else { return }
        let placement = placement(on: screen)
        content.setDetached(placement.detached)
        if panel.frame != placement.frame { panel.setFrame(placement.frame, display: true) }
    }

    private func animate() {
        animationTimer?.invalidate()
        animationTimer = nil
        advancePresentation()
        guard !transition.isFinished(at: ProcessInfo.processInfo.systemUptime) else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.advancePresentation() }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func advancePresentation() {
        let now = ProcessInfo.processInfo.systemUptime
        content.present(transition.pose(at: now))
        guard transition.isFinished(at: now) else { return }
        animationTimer?.invalidate()
        animationTimer = nil
        if dismissing {
            content.setPresented(false)
            panel?.orderOut(nil)
        }
    }

    func stop() {
        sessionSuspended = true
        dismiss(animated: false)
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.close()
        panel = nil
    }
}

private final class TrackNotificationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
