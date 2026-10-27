import Foundation

struct TrackAnnouncement: Equatable {
    let title: String
    let artist: String
    let bundleIdentifier: String
    let album: String
    let artworkData: Data?

    init(state: MediaState) {
        title = state.title
        artist = state.artist
        bundleIdentifier = state.bundleIdentifier
        album = state.album
        artworkData = state.artworkData
    }

    func hasSameTrack(as other: TrackAnnouncement) -> Bool {
        title == other.title && artist == other.artist && bundleIdentifier == other.bundleIdentifier
    }
}

/// Observe successful media reads only. Pause/resume, reconnects, and metadata
/// ID changes must not repeatedly announce the same visible song information.
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
        guard state.playing, let candidate else { return nil }
        if let lastAnnouncement, candidate.hasSameTrack(as: lastAnnouncement) { return nil }
        lastAnnouncement = candidate
        return enabled ? candidate : nil
    }
}
