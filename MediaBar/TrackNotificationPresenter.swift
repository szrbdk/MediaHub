import AppKit
import QuartzCore

/// An app-owned overlay; never activates MediaBar or requests notification access.
final class TrackNotificationPresenter {
    private var panel: TrackNotificationPanel?
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

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled { dismiss(animated: false) }
    }

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
        if panel?.isVisible == true { (panel?.contentView as? TrackNotificationView)?.update(updated) }
    }

    private func present(_ announcement: TrackAnnouncement) {
        guard enabled, !suspended else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width = min(400, screen.frame.width - 32)
        // Keep the floating card below a physical notch, with no connecting stem.
        let height = 112 + screen.safeAreaInsets.top
        let visibleFrame = NSRect(x: screen.frame.midX - width / 2,
                                  y: screen.frame.maxY - height, width: width, height: height)
        let hiddenFrame = visibleFrame.offsetBy(dx: 0, dy: height + 2)
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
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary,
                                         .stationary, .ignoresCycle]
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = TrackNotificationView(frame: NSRect(origin: .zero, size: visibleFrame.size))
            panel = window
        }
        if let previousScreen = window.screen, previousScreen != screen { window.orderOut(nil) }
        (window.contentView as? TrackNotificationView)?.update(announcement)
        if !window.isVisible {
            window.setFrame(hiddenFrame, display: false)
            window.alphaValue = 0
        }
        window.orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(visibleFrame, display: true)
            window.animator().alphaValue = 1
        }
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            self.dismiss(animated: true)
        }
        pendingDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.28, execute: work)
    }

    private func dismiss(animated: Bool) {
        generation += 1
        let expectedGeneration = generation
        pendingShow?.cancel()
        pendingDismiss?.cancel()
        currentAnnouncement = nil
        guard let panel, panel.isVisible else { return }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        let hiddenFrame = panel.frame.offsetBy(dx: 0, dy: panel.frame.height + 2)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(hiddenFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard self?.generation == expectedGeneration else { return }
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
