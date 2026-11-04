import Foundation
import CoreGraphics

/// Clock-driven visibility; the presenter supplies pointer locations and uptime.
struct MiniPlayerState {
    enum Form { case expanded, compact, hidden, announcement }
    private(set) var form: Form = .expanded
    private var idleSince: Double?
    private var cornerSince: Double?
    private var announcementUntil: Double?
    private var returnForm: Form = .compact
    private var initializedTrack = false
    private var lastTrack: [String]?
    private var pendingTrack = false

    mutating func expand() { form = .expanded; idleSince = nil; cornerSince = nil; announcementUntil = nil }
    mutating func collapse(at now: Double) { form = .compact; idleSince = now; cornerSince = nil; announcementUntil = nil }

    mutating func observeTrack(_ state: MediaState, enabled: Bool, now: Double) {
        guard state.hasMedia else { return }
        let identity = [state.bundleIdentifier, state.title, state.artistText]
        if !initializedTrack { initializedTrack = true; lastTrack = identity; return }
        if lastTrack != identity { lastTrack = identity; pendingTrack = true }
        guard enabled else {
            pendingTrack = false
            if form == .announcement { form = returnForm; announcementUntil = nil; idleSince = now }
            return
        }
        guard pendingTrack, state.playing else { return }
        pendingTrack = false
        guard form != .expanded else { return }
        if form != .announcement { returnForm = form }
        form = .announcement
        announcementUntil = now + 3
    }

    static func frame(for form: Form, in screen: CGRect) -> CGRect {
        let size = form == .expanded || form == .announcement
            ? CGSize(width: min(336, screen.width), height: 96) : CGSize(width: 64, height: 64)
        return CGRect(x: screen.maxX - size.width, y: screen.minY, width: size.width, height: size.height)
    }

    static func collapsedFrame(in screen: CGRect) -> CGRect {
        CGRect(x: screen.maxX - 1, y: screen.minY, width: 1, height: 1)
    }

    mutating func update(at now: Double, pointerInside: Bool, pointerInCorner: Bool) {
        switch form {
        case .expanded: break
        case .announcement:
            if now >= (announcementUntil ?? now) {
                form = returnForm
                idleSince = now
                cornerSince = nil
                announcementUntil = nil
            }
        case .compact:
            if pointerInside { idleSince = nil }
            else {
                if idleSince == nil { idleSince = now }
                if now - (idleSince ?? now) >= 3 { form = .hidden; cornerSince = nil }
            }
        case .hidden:
            if pointerInCorner {
                if cornerSince == nil { cornerSince = now }
                if now - (cornerSince ?? now) >= 0.2 {
                    form = .compact; idleSince = nil; cornerSince = nil
                }
            } else { cornerSince = nil }
        }
    }
}

/// One monotonic interpolation drives the surface and content together.
/// Retargeting starts at the current pose, never an obsolete window frame.
struct MiniPlayerTransition {
    struct Pose {
        var size: CGSize
        var wide: CGFloat
        var opacity: CGFloat
        static func target(_ form: MiniPlayerState.Form) -> Pose {
            switch form {
            case .expanded, .announcement: return Pose(size: CGSize(width: 336, height: 96), wide: 1, opacity: 1)
            case .compact: return Pose(size: CGSize(width: 64, height: 64), wide: 0, opacity: 1)
            case .hidden: return Pose(size: .zero, wide: 0, opacity: 0)
            }
        }
    }
    private var source = Pose.target(.hidden)
    private var destination = Pose.target(.hidden)
    private var beganAt: Double = 0
    private var duration: Double = 0

    func pose(at now: Double) -> Pose {
        let progress = duration > 0 ? min(1, max(0, (now - beganAt) / duration)) : 1
        let t = CGFloat(progress * progress * (3 - 2 * progress))
        return Pose(size: CGSize(width: source.size.width + (destination.size.width - source.size.width) * t,
                                 height: source.size.height + (destination.size.height - source.size.height) * t),
                    wide: source.wide + (destination.wide - source.wide) * t,
                    opacity: source.opacity + (destination.opacity - source.opacity) * t)
    }
    func isFinished(at now: Double) -> Bool { duration == 0 || now >= beganAt + duration }
    mutating func move(to form: MiniPlayerState.Form, at now: Double, animated: Bool) {
        source = pose(at: now)
        destination = .target(form)
        beganAt = now
        duration = animated ? 0.26 : 0
    }
}
