import AppKit
import OSLog

final class TouchBarPresenter {
    private let view: TouchBarView
    var onContextChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var unlockObserver: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    private var stopped = true
    private var presented = false
    private let logger = Logger(subsystem: "com.sezerbudak.MediaBar", category: "TouchBar")

    init(view: TouchBarView) { self.view = view }

    func start() {
        stopped = false
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.onContextChange?()
                if notification.name == NSWorkspace.willSleepNotification || notification.name == NSWorkspace.screensDidSleepNotification {
                    self?.pending?.cancel()
                    return
                }
                self?.schedule()
            })
        }
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                self?.onContextChange?()
                self?.schedule()
            }
        schedule()
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.presented = MBPresentTouchBar(self.view.bar)
            self.view.setPresented(self.presented)
            if !self.presented { self.logger.error("System Touch Bar presentation API unavailable") }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func stop() {
        stopped = true
        pending?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }
        unlockObserver = nil
        if presented { MBDismissTouchBar(view.bar) }
        presented = false
        view.setPresented(false)
    }
}
