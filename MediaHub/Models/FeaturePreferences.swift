import Foundation
import CoreGraphics

enum ScreenDisplayMode: String, CaseIterable {
    case notifications, miniPlayer, off
    var localizationKey: String { "display.mode.\(rawValue)" }
}

enum NotificationPosition: String, CaseIterable {
    case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight

    var isTop: Bool { [.topLeft, .topCenter, .topRight].contains(self) }
    var localizationKey: String { "notification.position.\(rawValue)" }

    func frame(in screen: CGRect, safeTop: CGFloat) -> CGRect {
        let width = min(400, screen.width - 32)
        let height = 112 + (isTop ? safeTop : 0)
        let x: CGFloat
        switch self {
        case .topLeft, .bottomLeft: x = screen.minX + 16
        case .topCenter, .bottomCenter: x = screen.midX - width / 2
        case .topRight, .bottomRight: x = screen.maxX - width - 16
        }
        return CGRect(x: x, y: isTop ? screen.maxY - height : screen.minY + 16,
                      width: width, height: height)
    }

    func hiddenFrame(for frame: CGRect) -> CGRect {
        frame.offsetBy(dx: 0, dy: (isTop ? 1 : -1) * (frame.height + 18))
    }
}

protocol PreferenceStore {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStore {}

final class FeaturePreferences {
    enum Feature: String {
        case notifications = "notificationsEnabled"
        case touchBar = "touchBarEnabled"
        case autoSkip = "autoSkipEnabled"
    }

    private let store: PreferenceStore

    init(store: PreferenceStore = UserDefaults.standard) { self.store = store }

    var screenDisplayMode: ScreenDisplayMode {
        get {
            if let raw = store.object(forKey: "screenDisplayMode") as? String,
               let mode = ScreenDisplayMode(rawValue: raw) { return mode }
            return isEnabled(.notifications) ? .notifications : .off
        }
        set { store.set(newValue.rawValue, forKey: "screenDisplayMode") }
    }

    var notificationPosition: NotificationPosition {
        get {
            (store.object(forKey: "notificationPosition") as? String)
                .flatMap(NotificationPosition.init(rawValue:)) ?? .topCenter
        }
        set { store.set(newValue.rawValue, forKey: "notificationPosition") }
    }

    func isEnabled(_ feature: Feature) -> Bool {
        // Preserve the current behavior for installations without saved choices.
        store.object(forKey: feature.rawValue) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool, for feature: Feature) {
        store.set(enabled, forKey: feature.rawValue)
    }
}
