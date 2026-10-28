import Foundation

struct TrackAnnouncement: Equatable {
    let title: String
    let artist: String
    let bundleIdentifier: String
    let album: String
    let artworkData: Data?
    let playing: Bool

    init(state: MediaState) {
        title = state.title
        artist = state.artist
        bundleIdentifier = state.bundleIdentifier
        album = state.album
        artworkData = state.artworkData
        playing = state.playing
    }

    func hasSameTrack(as other: TrackAnnouncement) -> Bool {
        title == other.title && artist == other.artist && bundleIdentifier == other.bundleIdentifier
    }
}

/// Observe successful media reads only. Announce playback transitions once,
/// preserving the last known state across transient missing-media snapshots.
struct TrackAnnouncementState {
    private var initialized = false
    private var lastAnnouncement: TrackAnnouncement?

    mutating func observe(_ state: MediaState, enabled: Bool = true) -> TrackAnnouncement? {
        let candidate = state.hasMedia ? TrackAnnouncement(state: state) : nil
        if !initialized {
            initialized = true
            lastAnnouncement = candidate
            return nil
        }
        guard let candidate else { return nil }
        let sameTrack = lastAnnouncement.map { candidate.hasSameTrack(as: $0) } ?? false
        let playbackChanged = sameTrack && candidate.playing != lastAnnouncement?.playing
        lastAnnouncement = candidate
        guard playbackChanged || (!sameTrack && candidate.playing) else { return nil }
        return enabled ? candidate : nil
    }
}
