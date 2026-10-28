import Foundation

struct AutoSkipState {
    enum Decision: Equatable { case none, skip, limitReached }
    private var initialized = false
    private var currentIdentity: [String]?
    private var evaluated = false
    private var consecutiveSkips = 0
    private var lastSkipAt: Double?
    private(set) var limitReached = false

    private func identity(_ state: MediaState) -> [String] {
        [state.bundleIdentifier, blacklistKey(state.title), blacklistKey(state.artistText)]
    }

    mutating func ignoreCurrent(_ state: MediaState) {
        initialized = true
        if state.hasMedia { currentIdentity = identity(state) }
        evaluated = true
    }

    mutating func resetLimit() {
        consecutiveSkips = 0
        lastSkipAt = nil
        limitReached = false
    }

    mutating func observe(_ state: MediaState, blacklist: BlacklistDocument, enabled: Bool, now: Double) -> Decision {
        if !initialized {
            initialized = true
            if state.hasMedia { currentIdentity = identity(state); evaluated = true }
            return .none
        }
        guard state.hasMedia else { return .none }
        let next = identity(state)
        if next != currentIdentity { currentIdentity = next; evaluated = false }
        guard enabled else { evaluated = true; resetLimit(); return .none }
        guard !evaluated, state.playing else { return .none }
        evaluated = true
        guard blacklist.matches(state) else { resetLimit(); return .none }
        if let lastSkipAt, now - lastSkipAt > 30 { resetLimit() }
        guard !limitReached, consecutiveSkips < 10 else {
            limitReached = true
            return .limitReached
        }
        consecutiveSkips += 1
        lastSkipAt = now
        return .skip
    }
}
