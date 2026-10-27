import Foundation

// Foundation-only executable. It never imports AppKit, connects to the XPC
// service, sends Apple Events, launches MediaBar or presents a Touch Bar.
var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    guard condition() else { fatalError(message) }
}

func payload(playing: Bool = true, rate: Double = 1) -> [String: Any] {
    ["title": "Track", "artist": "Artist", "bundleIdentifier": "com.apple.Music",
     "durationMicros": 180_000_000.0, "elapsedTimeMicros": 30_000_000.0,
     "timestampEpochMicros": 1_000_000_000.0, "playbackRate": rate, "playing": playing]
}

let advancing = PlaybackTimeline(payload: payload(), hasMedia: true, now: 1000)
expect(advancing.isValid && advancing.isAdvancing, "Playing timeline should advance")
expect(advancing.position(at: 1010) == 40, "Position should advance by elapsed wall time")
expect(advancing.position(at: 900) == 30, "Earlier wall time must not reverse playback")
expect(advancing.position(at: 2000) == 180, "Position must stop at duration")
let paused = PlaybackTimeline(payload: payload(playing: false), hasMedia: true, now: 1000)
expect(!paused.isAdvancing && paused.position(at: 1010) == 30, "Paused position must remain fixed")
let faster = PlaybackTimeline(payload: payload(rate: 2), hasMedia: true, now: 1000)
expect(faster.position(at: 1010) == 50, "Playback speed must affect position")
let invalidRate = PlaybackTimeline(payload: payload(rate: .nan), hasMedia: true, now: 1000)
expect(!invalidRate.isAdvancing, "Non-finite playback rate must not advance")
expect(!PlaybackTimeline(payload: payload(), hasMedia: false).isValid, "No media must invalidate the timeline")

for duration in [0.0, -1.0, Double.nan, Double.infinity] {
    var data = payload()
    data["durationMicros"] = duration
    expect(!PlaybackTimeline(payload: data, hasMedia: true).isValid, "Invalid duration must be rejected")
}
var missing = payload()
missing.removeValue(forKey: "elapsedTimeMicros")
expect(!PlaybackTimeline(payload: missing, hasMedia: true).isValid, "Missing elapsed time must hide timeline")
var invalidElapsed = payload()
invalidElapsed["elapsedTimeMicros"] = Double.nan
expect(!PlaybackTimeline(payload: invalidElapsed, hasMedia: true).isValid, "Non-finite elapsed time must be rejected")
var negativeElapsed = payload()
negativeElapsed["elapsedTimeMicros"] = -1_000_000.0
expect(PlaybackTimeline(payload: negativeElapsed, hasMedia: true, now: 1000).position(at: 1000) == 0, "Negative position must clamp to zero")
var invalidTimestamp = payload()
invalidTimestamp["timestampEpochMicros"] = Double.nan
expect(PlaybackTimeline(payload: invalidTimestamp, hasMedia: true, now: 1000).position(at: 1010) == 40, "Invalid timestamp should use snapshot time")
expect(advancing.seekMicroseconds(fraction: -1) == 0, "Seek must clamp at start")
expect(advancing.seekMicroseconds(fraction: 2) == 180_000_000, "Seek must clamp at end")
expect(advancing.seekMicroseconds(fraction: 0.5) == 90_000_000, "Seek fraction must map to duration")
expect(advancing.seekMicroseconds(fraction: .nan) == nil, "NaN seek must be rejected")
expect(advancing.seekMicroseconds(fraction: .infinity) == nil, "Infinite seek must be rejected")
expect(PlaybackTimeline().seekMicroseconds(fraction: 0.5) == nil, "Invalid timeline cannot seek")
var overflow = payload()
overflow["durationMicros"] = Double.greatestFiniteMagnitude
expect(PlaybackTimeline(payload: overflow, hasMedia: true).seekMicroseconds(fraction: 1) == nil, "Overflowing seek must be rejected")
expect(PlaybackTimeline.format(65) == "1:05", "Minute formatting")
expect(PlaybackTimeline.format(3661) == "1:01:01", "Hour formatting")
expect(PlaybackTimeline.format(-1) == "0:00", "Negative display time")
expect(PlaybackTimeline.format(.infinity) == "–:––", "Infinite display time must not crash")

let music = MediaState(payload: payload(), now: 1000)
expect(music.hasMedia && music.isMusic && !music.isPodcast, "Music source detection")
var podcastPayload = payload()
podcastPayload["bundleIdentifier"] = "com.apple.podcasts.helper"
podcastPayload["parentApplicationBundleIdentifier"] = "com.apple.podcasts"
let podcast = MediaState(payload: podcastPayload)
expect(podcast.isPodcast && podcast.bundleIdentifier == "com.apple.podcasts", "Parent player should own controls")
var emptyParent = payload()
emptyParent["parentApplicationBundleIdentifier"] = ""
expect(MediaState(payload: emptyParent).isMusic, "Empty parent should fall back to bundle identifier")
var changedTrack = payload()
changedTrack["uniqueIdentifier"] = 42
expect(MediaState(payload: changedTrack).trackKey != music.trackKey, "Distinct track IDs must reset interactions")
var collisionA = payload()
var collisionB = payload()
collisionA["title"] = "a|b"; collisionA["artist"] = "c"
collisionB["title"] = "a"; collisionB["artist"] = "b|c"
expect(MediaState(payload: collisionA).trackKey != MediaState(payload: collisionB).trackKey, "Track identity must not collide on delimiters")
expect(!MediaState(payload: [:]).hasMedia && !MediaState(payload: [:]).timeline.isValid, "Empty media must clear controls")

var favorite = FavoriteRequestState()
favorite.changeTrack(to: "first")
let firstRequest = favorite.begin()!
expect(favorite.begin() == nil, "Duplicate favorite taps must be locked")
favorite.finish(firstRequest, stillWaiting: true)
expect(favorite.isPending, "Unconfirmed favorite must stay locked")
favorite.resolveRead(for: "other", observedRequestID: firstRequest, confirmed: true, failed: false)
expect(favorite.isPending, "A different track cannot resolve a pending request")
favorite.resolveRead(for: "first", observedRequestID: firstRequest, confirmed: true, failed: false)
expect(!favorite.isPending, "Confirmed favorite must unlock")
let oldRequest = favorite.begin()!
favorite.changeTrack(to: "second")
expect(!favorite.isPending, "Track change must clear pending request")
let newRequest = favorite.begin()!
favorite.finish(oldRequest, stillWaiting: false)
expect(favorite.requestID == newRequest, "A stale reply cannot unlock a newer request")
favorite.resolveRead(for: "first", observedRequestID: oldRequest, confirmed: false, failed: true)
expect(favorite.isPending, "A stale read error cannot unlock the current request")
let staleReadAccepted = favorite.resolveRead(for: "second", observedRequestID: nil, confirmed: false, failed: true)
expect(!staleReadAccepted && favorite.isPending, "A read started before a tap cannot unlock that newer request")
favorite.resolveRead(for: "second", observedRequestID: newRequest, confirmed: false, failed: true)
expect(!favorite.isPending, "A real current-track failure must unlock retry")

print("Passed \(assertions) model assertions; no app or media service was launched.")
