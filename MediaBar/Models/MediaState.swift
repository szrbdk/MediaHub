import Foundation

struct MediaState {
    var title = ""
    var artist = ""
    var bundleIdentifier = ""
    var trackKey = ""
    var playing = false
    var timeline = PlaybackTimeline()
    var favorite = false
    var favoritePending = false
    var hasMedia: Bool { !title.isEmpty }
    var isMusic: Bool { bundleIdentifier == "com.apple.Music" }
    var isPodcast: Bool { bundleIdentifier == "com.apple.podcasts" }

    init() {}

    init(payload: [String: Any], now: Double = Date().timeIntervalSince1970) {
        title = payload["title"] as? String ?? ""
        artist = payload["artist"] as? String ?? payload["album"] as? String ?? ""
        let parent = payload["parentApplicationBundleIdentifier"] as? String ?? ""
        bundleIdentifier = parent.isEmpty ? payload["bundleIdentifier"] as? String ?? "" : parent
        let identity = payload["contentItemIdentifier"] ?? payload["uniqueIdentifier"] ?? ""
        // Encoding components avoids delimiter collisions in titles and artists.
        trackKey = [bundleIdentifier, title, artist, String(describing: identity)]
            .map { "\($0.utf8.count):\($0)" }.joined()
        playing = payload["playing"] as? Bool ?? false
        timeline = PlaybackTimeline(payload: payload, hasMedia: hasMedia, now: now)
    }
}

enum MediaAction {
    case togglePlayback, previous, next, openPlayer, addFavorite
    case beginSeeking(forward: Bool)
    case endSeeking
    case seek(fraction: Double, trackKey: String)
}
