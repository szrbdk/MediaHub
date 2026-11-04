import AppKit

/// Owns the nonactivating screen overlay. Media commands stay in MediaController.
final class MiniPlayerPresenter {
    var onAction: ((MediaAction) -> Void)?
    private let content = MiniPlayerView(frame: .zero)
    private var panel: MiniPlayerPanel?
    private var visibility = MiniPlayerState()
    private var timer: Timer?
    private var animationTimer: Timer?
    private var enabled = false
    private var asleep = false
    private var locked = false
    private var inactiveSession = false
    private var suspended: Bool { asleep || locked || inactiveSession }
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var transition = MiniPlayerTransition()
    private var appliedForm: MiniPlayerState.Form?
    private var screenFrame: NSRect?

    func start() {
        content.onAction = { [weak self] in self?.onAction?($0) }
        content.onExpand = { [weak self] in self?.visibility.expand(); self?.apply(animated: true) }
        content.onCollapse = { [weak self] in
            self?.visibility.collapse(at: ProcessInfo.processInfo.systemUptime)
            self?.apply(animated: true)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.asleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.asleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.inactiveSession = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.inactiveSession = false }
        observe(DistributedNotificationCenter.default(), NSNotification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(DistributedNotificationCenter.default(), NSNotification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.screenFrame = nil }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         change: @escaping (MiniPlayerPresenter) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            change(self)
            if self.suspended { self.hideImmediately() }
            else { self.apply(animated: false) }
        }
        observers.append((center, token))
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        timer?.invalidate()
        timer = nil
        if enabled {
            visibility.expand()
            apply(animated: true)
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else { hideImmediately() }
    }

    func render(_ state: MediaState) { content.render(state) }

    func observeTrack(_ state: MediaState, allowed: Bool) {
        visibility.observeTrack(state, enabled: enabled && !suspended && allowed,
                                now: ProcessInfo.processInfo.systemUptime)
        if enabled, appliedForm != visibility.form { apply(animated: true) }
    }

    private func tick() {
        guard enabled, !suspended, let screen = NSScreen.screens.first else { return }
        let pointer = NSEvent.mouseLocation
        let corner = NSRect(x: screen.frame.maxX - 24, y: screen.frame.minY, width: 24, height: 24)
        visibility.update(at: ProcessInfo.processInfo.systemUptime,
                          pointerInside: pointerIsOnSurface(pointer),
                          pointerInCorner: corner.contains(pointer))
        if appliedForm != visibility.form || screenFrame != screen.frame { apply(animated: true) }
        advancePresentation()
        if visibility.form == .expanded { content.refreshTimeline() }
    }

    private func apply(animated: Bool) {
        guard enabled, !suspended, let screen = NSScreen.screens.first else { return }
        let form = visibility.form
        // Keep the window and text layout fixed. Only the drawn surface morphs.
        let frame = MiniPlayerState.frame(for: .expanded, in: screen.frame)
        let window: MiniPlayerPanel
        if let panel { window = panel }
        else {
            window = MiniPlayerPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            // Float above ordinary apps, below Dock, menus and system overlays.
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary,
                                         .stationary, .ignoresCycle]
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = content
            panel = window
        }
        appliedForm = form
        // Cancel a drag whenever its controls disappear or the screen changes.
        if screenFrame != screen.frame { content.cancelSeek() }
        screenFrame = screen.frame
        window.setFrame(frame, display: false)
        content.setForm(form)
        transition.move(to: form, at: ProcessInfo.processInfo.systemUptime,
                        animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if form != .hidden {
            window.orderFrontRegardless()
        }
        advancePresentation()
        animationTimer?.invalidate()
        animationTimer = nil
        if !transition.isFinished(at: ProcessInfo.processInfo.systemUptime) {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.advancePresentation() }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        }
    }

    private func pointerIsOnSurface(_ point: NSPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return content.containsSurface(content.convert(panel.convertPoint(fromScreen: point), from: nil))
    }

    private func advancePresentation() {
        let now = ProcessInfo.processInfo.systemUptime
        content.present(transition.pose(at: now))
        let finished = transition.isFinished(at: now)
        if finished { animationTimer?.invalidate(); animationTimer = nil }
        // Preserve an existing mouse capture (especially slider drags) until up.
        let capturedPress = NSEvent.pressedMouseButtons & 1 != 0 && panel?.ignoresMouseEvents == false
        panel?.ignoresMouseEvents = !finished || visibility.form == .announcement || visibility.form == .hidden
            || (!capturedPress && !pointerIsOnSurface(NSEvent.mouseLocation))
        if finished, visibility.form == .hidden { panel?.orderOut(nil) }
    }

    private func hideImmediately() {
        animationTimer?.invalidate()
        animationTimer = nil
        transition.move(to: .hidden, at: ProcessInfo.processInfo.systemUptime, animated: false)
        appliedForm = nil
        content.cancelSeek()
        panel?.orderOut(nil)
    }

    func stop() {
        enabled = false
        timer?.invalidate()
        timer = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        hideImmediately()
        panel?.close()
        panel = nil
    }
}

private final class MiniPlayerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
