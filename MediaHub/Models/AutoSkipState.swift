import Foundation

struct AutoSkipState {
    enum Direction: Equatable {
        case previous, next
        var command: Int { self == .previous ? 5 : 4 }
    }
    enum Decision: Equatable {
        case none, skip(Direction), limitReached
        var skipDirection: Direction? { if case .skip(let direction) = self { return direction }; return nil }
    }
    private struct Navigation {
        let id = UUID()
        let direction: Direction
        let origin: [String]
        let issuedAt: Double
    }
    private var initialized = false
    private var currentIdentity: [String]?
    private var evaluated = false
    private var consecutiveSkips = 0
    private var lastSkipAt: Double?
    private var navigation: Navigation?
    private var currentDirection: Direction = .next
    private var chainDirection: Direction?
    private(set) var limitReached = false

    private func identity(_ state: MediaState) -> [String] {
        [state.bundleIdentifier, blacklistKey(state.title), blacklistKey(state.artistText)]
    }

    mutating func navigate(_ direction: Direction, from state: MediaState, now: Double) -> UUID {
        let request = Navigation(direction: direction, origin: identity(state), issuedAt: now)
        navigation = request
        chainDirection = nil
        return request.id
    }

    mutating func navigationFailed(_ id: UUID) {
        guard navigation?.id == id else { return }
        navigation = nil
    }

    mutating func skipFailed(for state: MediaState) {
        guard currentIdentity == identity(state) else { return }
        chainDirection = nil
        currentDirection = .next
        // Keep evaluated set so a failed command is not retried on this track.
    }

    mutating func ignoreCurrent(_ state: MediaState) {
        initialized = true
        if state.hasMedia { currentIdentity = identity(state) }
        evaluated = true
        navigation = nil
        chainDirection = nil
        currentDirection = .next
    }

    mutating func resetLimit() {
        consecutiveSkips = 0
        lastSkipAt = nil
        limitReached = false
        navigation = nil
        chainDirection = nil
        currentDirection = .next
    }

    mutating func observe(_ state: MediaState, blacklist: BlacklistDocument, enabled: Bool, now: Double) -> Decision {
        if let request = navigation, now - request.issuedAt > 10 { navigation = nil }
        if !initialized {
            initialized = true
            if state.hasMedia { currentIdentity = identity(state); evaluated = true }
            return .none
        }
        guard state.hasMedia else { return .none }
        let next = identity(state)
        if next != currentIdentity {
            let samePlayer = currentIdentity?.first == state.bundleIdentifier
            if let request = navigation, request.origin.first == state.bundleIdentifier, next != request.origin {
                currentDirection = request.direction
            } else if samePlayer, let chainDirection, let lastSkipAt, now - lastSkipAt <= 30 {
                currentDirection = chainDirection
            } else {
                currentDirection = .next
                chainDirection = nil
            }
            navigation = nil
            currentIdentity = next
            evaluated = false
        }
        guard enabled else { evaluated = true; resetLimit(); return .none }
        guard !evaluated, state.playing else { return .none }
        evaluated = true
        guard blacklist.matches(state) else { resetLimit(); return .none }
        if let lastSkipAt, now - lastSkipAt > 30 {
            // Reset the counter without losing the direction pinned to a paused selection.
            consecutiveSkips = 0
            limitReached = false
        }
        guard !limitReached, consecutiveSkips < 10 else {
            limitReached = true
            return .limitReached
        }
        consecutiveSkips += 1
        lastSkipAt = now
        chainDirection = currentDirection
        return .skip(currentDirection)
    }
}
