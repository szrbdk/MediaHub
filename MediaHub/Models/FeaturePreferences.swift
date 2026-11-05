import Foundation
import CoreGraphics

enum ScreenDisplayMode: String, CaseIterable {
    case notifications, miniPlayer, off
    var localizationKey: String { "display.mode.\(rawValue)" }
}

enum NotificationPosition: String, CaseIterable {
    case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight

    var isTop: Bool { [.topLeft, .topCenter, .topRight].contains(self) }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isRight: Bool { self == .topRight || self == .bottomRight }
    var localizationKey: String { "notification.position.\(rawValue)" }

    func frame(in screen: CGRect, safeTop: CGFloat, detached: Bool = false, menuBarHeight: CGFloat = 0) -> CGRect {
        let width = min(336, screen.width)
        let height: CGFloat = 96
        let x: CGFloat
        switch self {
        case .topLeft, .bottomLeft: x = screen.minX + (detached ? 12 : 0)
        case .topCenter, .bottomCenter: x = screen.midX - width / 2
        case .topRight, .bottomRight: x = screen.maxX - width - (detached ? 12 : 0)
        }
        let topInset = detached ? max(safeTop, menuBarHeight) + 8 : safeTop
        return CGRect(x: x, y: isTop ? screen.maxY - topInset - height : screen.minY,
                      width: width, height: height)
    }

    func surfaceRect(size: CGSize, in canvas: CGSize) -> CGRect {
        let x = isLeft ? 0 : (isRight ? canvas.width - size.width : (canvas.width - size.width) / 2)
        return CGRect(x: x, y: isTop ? canvas.height - size.height : 0, width: size.width, height: size.height)
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
