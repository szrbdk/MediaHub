import Foundation

/// A request stays locked while Music reports an unconfirmed result. Old
/// callbacks cannot unlock a request started for a later track.
struct FavoriteRequestState {
    private(set) var trackKey = ""
    private(set) var requestID: UUID?
    var isPending: Bool { requestID != nil }

    mutating func changeTrack(to key: String) {
        guard key != trackKey else { return }
        trackKey = key
        requestID = nil
    }
    mutating func begin() -> UUID? {
        guard !isPending else { return nil }
        let id = UUID()
        requestID = id
        return id
    }
    mutating func finish(_ id: UUID, stillWaiting: Bool) {
        guard requestID == id, !stillWaiting else { return }
        requestID = nil
    }
    @discardableResult
    mutating func resolveRead(for key: String, observedRequestID: UUID?, confirmed: Bool, failed: Bool) -> Bool {
        guard key == trackKey, requestID == observedRequestID else { return false }
        if confirmed || failed { requestID = nil }
        return true
    }
}
