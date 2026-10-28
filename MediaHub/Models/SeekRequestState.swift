import Foundation

/// Command acceptance is not a playback-position acknowledgement. Keep the
/// requested timeline until consecutive player snapshots agree with it.
struct SeekRequestState {
    private(set) var requestID: UUID?
    private var target: PlaybackTimeline?
    private var latestPlayerTimeline = PlaybackTimeline()
    private var startedAt: Double = 0
    private var accepted = false
    private var confirmations = 0
    var isPending: Bool { requestID != nil }

    mutating func begin(position: Double, timeline: PlaybackTimeline, now: Double) -> UUID {
        if !isPending { latestPlayerTimeline = timeline }
        var requested = timeline
        requested.elapsed = min(timeline.duration, max(0, position))
        requested.timestamp = now
        target = requested
        startedAt = now
        accepted = false
        confirmations = 0
        let id = UUID()
        requestID = id
        return id
    }

    func displayedTimeline(fallback: PlaybackTimeline) -> PlaybackTimeline {
        target ?? fallback
    }

    mutating func receive(_ timeline: PlaybackTimeline, now: Double) -> PlaybackTimeline {
        latestPlayerTimeline = timeline
        guard var requested = target else { return timeline }
        guard timeline.isValid, now - startedAt < 4 else {
            reset()
            return timeline
        }
        let expected = requested.position(at: now)
        if accepted && abs(timeline.position(at: now) - expected) < 1.5 {
            confirmations += 1
        } else {
            confirmations = 0
        }
        if confirmations >= 2 {
            reset()
            return timeline
        }
        // Preserve play/pause and rate changes without adopting stale positions.
        requested.elapsed = expected
        requested.timestamp = now
        requested.rate = timeline.rate
        target = requested
        return requested
    }

    /// Returns a fallback only for failure of the current request. Late replies
    /// from an earlier seek must not alter the new request or its displayed time.
    mutating func complete(_ id: UUID, success: Bool) -> PlaybackTimeline? {
        guard requestID == id else { return nil }
        if success {
            accepted = true
            return nil
        }
        let fallback = latestPlayerTimeline
        reset()
        return fallback
    }

    mutating func reset() {
        requestID = nil
        target = nil
        confirmations = 0
        accepted = false
    }
}
