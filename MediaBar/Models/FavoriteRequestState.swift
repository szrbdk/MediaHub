import Foundation

/// The star changes optimistically, but another tap is accepted only after the
/// current operation finishes. Injected monotonic time bounds verification.
struct FavoriteRequestState {
    struct Write: Equatable {
        let id = UUID()
        let target: Bool
    }

    private(set) var trackKey = ""
    private(set) var confirmed = false
    private(set) var write: Write?
    private(set) var confirmationDeadline: Double?
    private(set) var readToken = UUID()

    var displayed: Bool { write?.target ?? confirmed }
    var isPending: Bool { write != nil }
    var isConfirming: Bool { confirmationDeadline != nil }

    mutating func changeTrack(to key: String) {
        guard key != trackKey else { return }
        self = FavoriteRequestState()
        trackKey = key
    }

    mutating func beginToggle() -> Write? {
        guard !trackKey.isEmpty, !isPending else { return nil }
        let request = Write(target: !confirmed)
        write = request
        readToken = UUID()
        return request
    }

    @discardableResult
    mutating func completeWrite(_ id: UUID, observed: Bool?, failed: Bool, at now: Double) -> Bool {
        guard let request = write, request.id == id, !isConfirming else { return false }
        readToken = UUID()
        if failed || observed == nil { finish(success: false) }
        else if observed == request.target { finish(success: true) }
        else { confirmationDeadline = now + 5 }
        return true
    }

    @discardableResult
    mutating func receiveRead(token: UUID, observed: Bool?, at now: Double) -> Bool {
        guard token == readToken else { return false }
        if let request = write {
            // A periodic read must never acknowledge a write still in flight.
            guard let deadline = confirmationDeadline else { return false }
            if now >= deadline || observed == nil { finish(success: false) }
            else if observed == request.target { finish(success: true) }
            // Keep the optimistic star and lock while Music's state catches up.
        } else if let observed {
            confirmed = observed
        }
        return true
    }

    @discardableResult
    mutating func expire(at now: Double) -> Bool {
        guard let deadline = confirmationDeadline, now >= deadline else { return false }
        finish(success: false)
        return true
    }

    private mutating func finish(success: Bool) {
        guard let request = write else { return }
        if success { confirmed = request.target }
        write = nil
        confirmationDeadline = nil
        readToken = UUID()
    }
}
