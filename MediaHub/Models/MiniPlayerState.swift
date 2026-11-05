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
    private var announcements = TrackAnnouncementState()

    mutating func expand() { form = .expanded; idleSince = nil; cornerSince = nil; announcementUntil = nil }
    mutating func collapse(at now: Double) { form = .compact; idleSince = now; cornerSince = nil; announcementUntil = nil }

    mutating func observeTrack(_ state: MediaState, enabled: Bool, now: Double) {
        let announcement = announcements.observe(state, enabled: enabled)
        guard enabled else {
            if form == .announcement { form = returnForm; announcementUntil = nil; idleSince = now }
            return
        }
        guard announcement != nil, form != .expanded else { return }
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
        // Keep the surface visible while it retracts. Fading throughout the
        // entire shrink made the card appear to vanish before reaching the corner.
        let fadePhase = destination.opacity < source.opacity && duration > 0
            ? min(1, max(0, (progress - 0.85) / 0.15)) : progress
        let opacityT = CGFloat(fadePhase * fadePhase * (3 - 2 * fadePhase))
        return Pose(size: CGSize(width: source.size.width + (destination.size.width - source.size.width) * t,
                                 height: source.size.height + (destination.size.height - source.size.height) * t),
                    wide: source.wide + (destination.wide - source.wide) * t,
                    opacity: source.opacity + (destination.opacity - source.opacity) * opacityT)
    }
    func isFinished(at now: Double) -> Bool { duration == 0 || now >= beganAt + duration }
    mutating func move(to form: MiniPlayerState.Form, at now: Double, animated: Bool) {
        source = pose(at: now)
        destination = .target(form)
        beganAt = now
        duration = animated ? 0.26 : 0
    }
}
