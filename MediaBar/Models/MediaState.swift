import Foundation

struct MediaState {
    var title = ""
    var artist = ""
    var artistText = ""
    var artistNames: [String] = []
    var album = ""
    var artworkData: Data?
    var bundleIdentifier = ""
    var trackKey = ""
    var playing = false
    var timeline = PlaybackTimeline()
    var favorite = false
    var favoritePending = false
    var seekPending = false
    var canEditBlacklist = true
    var songBlacklisted = false
    var primaryArtistBlacklisted = false
    var hasMedia: Bool { !title.isEmpty }
    var isMusic: Bool { bundleIdentifier == "com.apple.Music" }
    var isPodcast: Bool { bundleIdentifier == "com.apple.podcasts" }
    var songBlacklistEntry: BlacklistEntry? {
        guard hasMedia, !blacklistKey(artistText).isEmpty else { return nil }
        return .song(BlacklistedSong(title: title, artistText: artistText))
    }
    var primaryArtistBlacklistEntry: BlacklistEntry? {
        if let first = artistNames.first { return .artist(BlacklistedArtist(name: first, match: .individual)) }
        guard !blacklistKey(artistText).isEmpty else { return nil }
        return .artist(BlacklistedArtist(name: artistText, match: .fullText))
    }

    init() {}

    init(payload: [String: Any], now: Double = Date().timeIntervalSince1970) {
        title = payload["title"] as? String ?? ""
        var seenArtists = Set<String>()
        artistNames = (payload["artistNames"] as? [String] ?? []).filter {
            let key = blacklistKey($0)
            return !key.isEmpty && seenArtists.insert(key).inserted
        }
        let rawArtist = payload["artist"] as? String ?? ""
        artistText = blacklistKey(rawArtist).isEmpty ? artistNames.joined(separator: " & ") : rawArtist
        artist = payload["artist"] as? String == nil && artistNames.isEmpty ? payload["album"] as? String ?? "" : artistText
        album = payload["album"] as? String ?? ""
        artworkData = payload["artworkData"] as? Data
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
    case togglePlayback, previous, next, addFavorite
    case toggleBlacklist(BlacklistEntry, trackKey: String)
    case beginSeeking(forward: Bool)
    case endSeeking
    case seek(fraction: Double, trackKey: String)
}
