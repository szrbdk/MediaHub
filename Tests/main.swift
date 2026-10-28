import Foundation

// Keep the shared localization's default preference in memory during model tests.
UserDefaults.standard.setVolatileDomain(["appLanguage": "en"], forName: UserDefaults.argumentDomain)

// Foundation-only executable. It never imports AppKit, connects to the XPC
// service, sends Apple Events, launches MediaHub or presents a Touch Bar.
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

// Favorite verification times are injected; these tests never contact Music.
var favorite = FavoriteRequestState()
expect(favorite.beginToggle() == nil, "No track must reject favorite taps")
favorite.changeTrack(to: "first")
let initialFavoriteRead = favorite.readToken
favorite.receiveRead(token: initialFavoriteRead, observed: false, at: 0)
let firstRequest = favorite.beginToggle()!
expect(firstRequest.target && favorite.displayed, "Adding must fill the star before Music responds")
expect(favorite.isPending, "The button must lock as soon as the tap is accepted")
expect(favorite.beginToggle() == nil, "Repeated taps must be ignored while writing")
expect(!favorite.expire(at: 100), "Elapsed time alone must not unlock a write that has not replied")
expect(favorite.isPending && favorite.beginToggle() == nil, "Even a very slow write must stay locked without queuing a second intent")
expect(!favorite.receiveRead(token: initialFavoriteRead, observed: false, at: 101), "A read started before a tap must not revert the star")
expect(!favorite.receiveRead(token: favorite.readToken, observed: false, at: 101), "An idle poll cannot resolve a write that has not replied")
expect(favorite.completeWrite(firstRequest.id, observed: true, failed: false, at: 102), "A matching write reply must be accepted")
expect(favorite.displayed && favorite.confirmed && !favorite.isPending, "Confirmation must immediately preserve the star and unlock")
let removal = favorite.beginToggle()!
expect(!removal.target && !favorite.displayed && favorite.isPending, "Removal must immediately empty the star and lock")
expect(!favorite.completeWrite(firstRequest.id, observed: true, failed: false, at: 102), "A duplicate old reply cannot finish a newer request")
expect(favorite.write?.id == removal.id && !favorite.displayed, "A stale reply must leave the removal unchanged")
favorite.completeWrite(removal.id, observed: false, failed: false, at: 102.1)
expect(!favorite.displayed && !favorite.confirmed && !favorite.isPending, "A confirmed false response must unlock removal")
let immediateNext = favorite.beginToggle()!
expect(immediateNext.target && favorite.isPending, "A fast reply must allow another tap without a fixed cooldown")
favorite.completeWrite(immediateNext.id, observed: true, failed: false, at: 102.2)
expect(favorite.confirmed && !favorite.isPending, "Ignoring repeated taps must not queue any follow-up writes")

// A lagging write result keeps both the optimistic appearance and the lock.
let laggingRemoval = favorite.beginToggle()!
favorite.completeWrite(laggingRemoval.id, observed: true, failed: false, at: 110)
expect(favorite.isConfirming && favorite.confirmationDeadline == 115, "A lagging reply must start bounded verification")
expect(!favorite.displayed && favorite.confirmed && favorite.isPending, "The star must remain empty while removal is being confirmed")
expect(favorite.beginToggle() == nil, "The button must remain locked during confirmation")
let removalRead = favorite.readToken
favorite.receiveRead(token: removalRead, observed: true, at: 111)
expect(!favorite.displayed && favorite.isPending, "A lagging snapshot must neither flicker nor unlock")
expect(!favorite.completeWrite(laggingRemoval.id, observed: false, failed: false, at: 111), "A duplicate write callback must not bypass verification")
expect(!favorite.expire(at: 114.99), "Confirmation must stay active before the deadline")
favorite.receiveRead(token: removalRead, observed: false, at: 114.99)
expect(!favorite.displayed && !favorite.confirmed && !favorite.isPending, "A matching verification read must unlock removal")
expect(!favorite.receiveRead(token: removalRead, observed: true, at: 115), "An old read cannot undo confirmed removal")

let laggingAdd = favorite.beginToggle()!
favorite.completeWrite(laggingAdd.id, observed: false, failed: false, at: 120)
favorite.receiveRead(token: favorite.readToken, observed: true, at: 121)
expect(favorite.displayed && favorite.confirmed && !favorite.isPending, "Delayed add confirmation must preserve the filled star and unlock")

// Failures restore the last confirmed appearance and permit an explicit retry.
let failedRemoval = favorite.beginToggle()!
favorite.completeWrite(failedRemoval.id, observed: nil, failed: true, at: 122)
expect(favorite.displayed && favorite.confirmed && !favorite.isPending, "Failed removal must silently restore the filled star and unlock")
let retryRemoval = favorite.beginToggle()!
expect(!retryRemoval.target, "A failed operation must permit an immediate explicit retry")
favorite.completeWrite(retryRemoval.id, observed: true, failed: false, at: 123)
let expiredRead = favorite.readToken
expect(favorite.expire(at: 128), "Verification must time out even when a callback is missing")
expect(favorite.displayed && !favorite.isPending, "Timeout must restore the confirmed state and unlock")
expect(!favorite.receiveRead(token: expiredRead, observed: false, at: 129), "Late verification cannot override a rollback")

var failedAdd = FavoriteRequestState()
failedAdd.changeTrack(to: "track")
let missingResponse = failedAdd.beginToggle()!
failedAdd.completeWrite(missingResponse.id, observed: nil, failed: false, at: 0)
expect(!failedAdd.displayed && !failedAdd.isPending, "A missing add response must roll back and unlock")
let contradictoryReply = failedAdd.beginToggle()!
failedAdd.completeWrite(contradictoryReply.id, observed: true, failed: true, at: 1)
expect(!failedAdd.displayed && !failedAdd.isPending, "An error must not be mistaken for success even when a value is returned")
let failedVerification = failedAdd.beginToggle()!
failedAdd.completeWrite(failedVerification.id, observed: false, failed: false, at: 2)
failedAdd.receiveRead(token: failedAdd.readToken, observed: nil, at: 3)
expect(!failedAdd.displayed && !failedAdd.isPending, "A failed verification read must roll back and unlock")
let boundaryWrite = failedAdd.beginToggle()!
failedAdd.completeWrite(boundaryWrite.id, observed: false, failed: false, at: 4)
failedAdd.receiveRead(token: failedAdd.readToken, observed: true, at: 9)
expect(!failedAdd.displayed && !failedAdd.isPending, "Confirmation at its deadline must be rejected")

// Track changes and returning to a track must invalidate all earlier callbacks.
let previousTrackWrite = favorite.beginToggle()!
let previousTrackRead = favorite.readToken
favorite.changeTrack(to: "second")
expect(!favorite.displayed && !favorite.isPending, "Track change must clear optimistic state and unlock")
let newTrackWrite = favorite.beginToggle()!
expect(newTrackWrite.target, "The new track must be immediately usable")
expect(!favorite.completeWrite(previousTrackWrite.id, observed: false, failed: false, at: 130), "The previous track cannot resolve the new write")
expect(!favorite.receiveRead(token: previousTrackRead, observed: true, at: 130), "An old track read must be ignored")
expect(favorite.write?.id == newTrackWrite.id && favorite.isPending, "Old callbacks must not unlock the new track")
favorite.changeTrack(to: "first")
expect(!favorite.completeWrite(previousTrackWrite.id, observed: false, failed: false, at: 131), "Returning to an old track must not revive its callbacks")
expect(!favorite.expire(at: 200), "An old timeout must not affect a new track")
favorite.receiveRead(token: favorite.readToken, observed: true, at: 201)
expect(favorite.displayed && favorite.confirmed, "Idle reads must still reflect changes made directly in Music")
let sameTrackRequest = favorite.beginToggle()!
favorite.changeTrack(to: "first")
expect(favorite.write?.id == sameTrackRequest.id && favorite.isPending, "Refreshing the same track must not reset the lock")

var seek = SeekRequestState()
let seekID = seek.begin(position: 90, timeline: advancing, now: 1000)
expect(seek.displayedTimeline(fallback: advancing).position(at: 1000) == 90, "Release should immediately display the requested position")
expect(seek.receive(advancing, now: 1000.5).position(at: 1000.5) == 90.5, "A stale player position must not pull the bar back")
var reportedTarget = advancing
reportedTarget.elapsed = 90
expect(abs(seek.receive(reportedTarget, now: 1000.6).position(at: 1000.6) - 90.6) < 0.000001, "Player data before command acceptance must preserve the requested timeline")
expect(seek.isPending, "A snapshot alone cannot acknowledge an unaccepted command")
expect(seek.complete(seekID, success: true) == nil && seek.isPending, "Command acceptance must not clear position confirmation")
_ = seek.receive(reportedTarget, now: 1001)
expect(seek.isPending, "A single matching snapshot should not unlock stale updates")
expect(seek.receive(advancing, now: 1001.5).position(at: 1001.5) == 91.5, "A stale snapshot after a matching one must still be ignored")
_ = seek.receive(reportedTarget, now: 1002)
expect(seek.isPending, "Stale data must reset consecutive confirmation count")
_ = seek.receive(reportedTarget, now: 1002.5)
expect(!seek.isPending, "Two consecutive matching player snapshots should finish the request")

let earlierSeek = seek.begin(position: 60, timeline: advancing, now: 1000)
let laterSeek = seek.begin(position: 120, timeline: advancing, now: 1000.1)
expect(seek.complete(earlierSeek, success: false) == nil && seek.requestID == laterSeek, "An earlier seek failure cannot cancel a newer seek")
expect(seek.displayedTimeline(fallback: advancing).position(at: 1000.1) == 120, "The latest released target must win")
let failedFallback = seek.complete(laterSeek, success: false)
expect(failedFallback?.elapsed == advancing.elapsed && !seek.isPending, "A real seek failure must restore the player timeline")

let timedOutSeek = seek.begin(position: 100, timeline: advancing, now: 1000)
_ = seek.complete(timedOutSeek, success: true)
let timeoutFallback = seek.receive(advancing, now: 1004)
expect(!seek.isPending && timeoutFallback.position(at: 1004) == 34, "An unsupported seek should eventually restore real player data")
_ = seek.begin(position: 100, timeline: advancing, now: 1000)
let lostMedia = seek.receive(PlaybackTimeline(), now: 1001)
expect(!seek.isPending && !lostMedia.isValid, "Losing media must clear a pending seek")
_ = seek.begin(position: 100, timeline: advancing, now: 1000)
seek.reset()
expect(!seek.isPending, "Track changes and shutdown must discard old seek state")

var announcements = TrackAnnouncementState()
expect(announcements.observe(music) == nil, "Startup must not announce an already-playing track")
expect(announcements.observe(music) == nil, "Repeated snapshots must not announce the same track")
var pausedMusic = music
pausedMusic.playing = false
expect(announcements.observe(pausedMusic)?.playing == false, "Pausing must announce the paused state")
expect(announcements.observe(pausedMusic) == nil, "Repeated paused snapshots must stay quiet")
expect(announcements.observe(music)?.playing == true, "Resuming must announce the playing state")
expect(announcements.observe(music) == nil, "Repeated playing snapshots must stay quiet")
var newMetadataID = payload()
newMetadataID["uniqueIdentifier"] = "late-id"
expect(announcements.observe(MediaState(payload: newMetadataID)) == nil, "An ID update with unchanged song information must not announce again")
var nextPayload = payload()
nextPayload["title"] = "Next track"
let nextTrack = MediaState(payload: nextPayload)
expect(announcements.observe(nextTrack)?.title == "Next track", "A playing track change must produce an announcement")
expect(announcements.observe(nextTrack) == nil, "A changed track must only announce once")
expect(announcements.observe(MediaState()) == nil, "Missing media must not produce a blank announcement")
expect(announcements.observe(nextTrack) == nil, "Reconnecting to the same track must not repeat its announcement")
var laterPayload = payload(playing: false)
laterPayload["title"] = "Later track"
expect(announcements.observe(MediaState(payload: laterPayload)) == nil, "A selected paused track waits until playback starts")
laterPayload["playing"] = true
expect(announcements.observe(MediaState(payload: laterPayload))?.title == "Later track", "Starting the newly selected track must announce it")
expect(announcements.observe(music)?.title == music.title, "Returning to an earlier track is a new track change")
var initiallyIdle = TrackAnnouncementState()
expect(initiallyIdle.observe(MediaState()) == nil, "An idle launch must remain quiet")
expect(initiallyIdle.observe(music) != nil, "Starting playback after an idle launch must announce the first track")
var initiallyPaused = TrackAnnouncementState()
expect(initiallyPaused.observe(pausedMusic) == nil, "Launching with paused media must stay quiet")
expect(initiallyPaused.observe(music)?.playing == true, "Resuming after a paused launch must announce")
var mutedPlayback = TrackAnnouncementState()
_ = mutedPlayback.observe(music)
expect(mutedPlayback.observe(pausedMusic, enabled: false) == nil, "Disabled notifications must consume pause transitions silently")
expect(mutedPlayback.observe(pausedMusic) == nil, "Re-enabling must not replay a suppressed pause")
expect(mutedPlayback.observe(music)?.playing == true, "The next resume must announce after re-enabling")
expect(mutedPlayback.observe(MediaState()) == nil, "Transient missing media must stay quiet")
expect(mutedPlayback.observe(music) == nil, "Reconnect without a playback change must stay quiet")
expect(mutedPlayback.observe(pausedMusic)?.playing == false, "Pause after reconnect must still announce")

var coverPayload = nextPayload
let coverBytes = Data([1, 2, 3, 4])
coverPayload["album"] = "Album name"
coverPayload["artworkData"] = coverBytes
let coveredTrack = MediaState(payload: coverPayload)
expect(coveredTrack.album == "Album name", "Album metadata must reach the app state")
expect(coveredTrack.artworkData == coverBytes, "Artwork must cross the model as binary data")
let coveredAnnouncement = announcements.observe(coveredTrack)
expect(coveredAnnouncement?.album == "Album name", "Announcements must carry the album name")
expect(coveredAnnouncement?.artworkData == coverBytes, "Announcements must carry the available cover")
coverPayload["artworkData"] = Data([5, 6, 7])
expect(announcements.observe(MediaState(payload: coverPayload)) == nil, "A cover update must not create a second notification")
coverPayload["album"] = "Updated album"
expect(announcements.observe(MediaState(payload: coverPayload)) == nil, "Late album metadata must not create a second notification")
expect(MediaState(payload: payload()).artworkData == nil, "A player without artwork must allow the fallback icon")

// Inject an in-memory store so preference tests never change the user's settings.
final class TestPreferenceStore: PreferenceStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
let preferenceStore = TestPreferenceStore()
let migratedPreferences = TestPreferenceStore()
let legacyPreferences: [String: Any] = ["notificationsEnabled": false, "touchBarEnabled": false,
    "autoSkipEnabled": true, "appLanguage": "tr", "unrelatedLegacyValue": "ignored"]
LegacyPreferencesMigration.migrate(store: migratedPreferences, legacyValues: legacyPreferences)
expect(!FeaturePreferences(store: migratedPreferences).isEnabled(.notifications), "Renaming must preserve disabled notifications")
expect(!FeaturePreferences(store: migratedPreferences).isEnabled(.touchBar), "Renaming must preserve disabled Touch Bar")
expect(FeaturePreferences(store: migratedPreferences).isEnabled(.autoSkip), "Renaming must preserve automatic skipping")
expect(migratedPreferences.values["appLanguage"] as? String == "tr", "Renaming must preserve the selected language before localization initializes")
expect(migratedPreferences.values["unrelatedLegacyValue"] == nil, "Migration must only copy application preferences")
migratedPreferences.set(true, forKey: "notificationsEnabled")
LegacyPreferencesMigration.migrate(store: migratedPreferences, legacyValues: legacyPreferences)
expect(FeaturePreferences(store: migratedPreferences).isEnabled(.notifications), "Legacy preferences must only migrate once")
let existingHubPreferences = TestPreferenceStore()
existingHubPreferences.set("en", forKey: "appLanguage")
existingHubPreferences.set(false, forKey: "autoSkipEnabled")
LegacyPreferencesMigration.migrate(store: existingHubPreferences, legacyValues: legacyPreferences)
expect(existingHubPreferences.values["appLanguage"] as? String == "en", "An existing MediaHub language must not be overwritten")
expect(!FeaturePreferences(store: existingHubPreferences).isEnabled(.autoSkip), "Existing MediaHub toggles must take precedence")
let freshHubPreferences = TestPreferenceStore()
LegacyPreferencesMigration.migrate(store: freshHubPreferences, legacyValues: [:])
expect(FeaturePreferences(store: freshHubPreferences).isEnabled(.notifications), "Fresh installations must retain default preferences")
expect(freshHubPreferences.values["appLanguage"] == nil, "Fresh installations must let localization select the initial language")
let resourceRoot = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MediaHub/Resources")
let languageStore = TestPreferenceStore()
let localization = Localization(store: languageStore, preferredLanguages: ["tr-TR"], resourcesURL: resourceRoot)
expect(localization.language == .tr, "First launch must select the system language")
expect(languageStore.values["appLanguage"] as? String == "tr", "First launch must save a concrete language")
expect(AppLanguage.allCases == [.en, .tr], "Only English and Turkish may be offered")
expect(AppLanguage.initial(preferredLanguages: ["tr_TR"]) == .tr, "Underscore locale identifiers must work")
expect(AppLanguage.initial(preferredLanguages: ["en-GB"]) == .en, "English system language must use English")
expect(AppLanguage.initial(preferredLanguages: ["de-DE", "tr-TR"]) == .en, "An unsupported primary system language must fall back to English")
expect(AppLanguage.initial(preferredLanguages: []) == .en, "Missing system language must fall back to English")
expect(localization.text("menu.quit") == "Çıkış", "Turkish must load from the actual strings resource")
localization.language = .en
expect(localization.text("menu.quit") == "Quit", "Changing language must immediately select the English table")
expect(localization.text("menu.language") == "Language", "All translations must switch together")
localization.language = .tr
expect(localization.text("menu.quit") == "Çıkış", "Switching back must not use cached English translations")
let restoredLanguage = Localization(store: languageStore, preferredLanguages: ["en-US"], resourcesURL: resourceRoot)
expect(restoredLanguage.language == .tr, "A saved choice must survive restart and system language changes")
expect(restoredLanguage.text("menu.language") == "Dil", "The saved language must select its translation table")
for invalid in ["system", "invalid"] {
    let migrationStore = TestPreferenceStore()
    migrationStore.values["appLanguage"] = invalid
    let migrated = Localization(store: migrationStore, preferredLanguages: ["en-US"], resourcesURL: resourceRoot)
    expect(migrated.language == .en, "Old and invalid choices must resolve from the system")
    expect(migrationStore.values["appLanguage"] as? String == "en", "Migration must persist a concrete language")
}
let englishFirstLaunch = Localization(store: TestPreferenceStore(), preferredLanguages: ["en-US"], resourcesURL: resourceRoot)
expect(englishFirstLaunch.language == .en, "English must be selected on first English-system launch")
func translations(_ language: String) -> [String: String] {
    let data = try! Data(contentsOf: resourceRoot.appendingPathComponent("\(language).lproj/Localizable.strings"))
    return try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
}
let englishStrings = translations("en")
let turkishStrings = translations("tr")
expect(Set(englishStrings.keys) == Set(turkishStrings.keys), "Both languages must cover the same keys")
expect(englishStrings.keys.allSatisfy { $0.contains(".") && !$0.contains(" ") }, "Translations must use stable identifiers rather than display text")
expect(!turkishStrings.values.contains(where: { $0.isEmpty }), "Translations must not be empty")
let preferences = FeaturePreferences(store: preferenceStore)
expect(preferences.isEnabled(.notifications), "Notifications should default to enabled")
expect(preferences.isEnabled(.touchBar), "Touch Bar should default to enabled")
preferences.setEnabled(false, for: .notifications)
expect(!preferences.isEnabled(.notifications) && preferences.isEnabled(.touchBar), "Notification and Touch Bar choices must be independent")
preferences.setEnabled(false, for: .touchBar)
let reloadedPreferences = FeaturePreferences(store: preferenceStore)
expect(!reloadedPreferences.isEnabled(.notifications) && !reloadedPreferences.isEnabled(.touchBar), "Recreating preferences must retain both disabled choices")
reloadedPreferences.setEnabled(true, for: .notifications)
expect(preferences.isEnabled(.notifications) && !preferences.isEnabled(.touchBar), "Re-enabling notifications must preserve the Touch Bar setting")
reloadedPreferences.setEnabled(true, for: .touchBar)
expect(FeaturePreferences(store: preferenceStore).isEnabled(.touchBar), "The re-enabled Touch Bar choice must also persist")
preferenceStore.values[FeaturePreferences.Feature.touchBar.rawValue] = "invalid"
expect(preferences.isEnabled(.touchBar), "An invalid saved value should fall back to enabled")

var mutedAnnouncements = TrackAnnouncementState()
_ = mutedAnnouncements.observe(music, enabled: false)
expect(mutedAnnouncements.observe(nextTrack, enabled: false) == nil, "Disabled notifications must suppress new-track announcements")
expect(mutedAnnouncements.observe(nextTrack, enabled: true) == nil, "Re-enabling must not replay a track seen while disabled")
expect(mutedAnnouncements.observe(music, enabled: true) != nil, "A subsequent track change must announce after re-enabling")

var blocked = BlacklistDocument()
let fullGroup = BlacklistEntry.artist(BlacklistedArtist(name: "A&B&C", match: .fullText))
expect(blocked.add(fullGroup), "A full artist-text entry should be accepted")
expect(!blocked.add(.artist(BlacklistedArtist(name: " a&b&c ", match: .fullText))), "Case and surrounding whitespace must not create duplicates")
func track(_ title: String = "Song", artist: String = "A&B&C", names: [String] = [], playing: Bool = true) -> MediaState {
    var data = payload(playing: playing)
    data["title"] = title
    data["artist"] = artist
    data["artistNames"] = names
    return MediaState(payload: data)
}
expect(blocked.matches(track()), "The exact blocked artist text must match")
expect(blocked.matches(track(artist: " a&b&c ")), "Matching ignores case and outer whitespace")
expect(!blocked.matches(track(artist: "B&A&C")), "Artist text order must be preserved")
expect(!blocked.matches(track(artist: "A & B & C")), "Internal spaces must remain significant")
expect(!blocked.matches(track(artist: "A")), "Full artist text must not be split into individuals")
expect(!blocked.matches(track(artist: "XA&B&C")), "Substring artist matches must not be used")
var individualList = BlacklistDocument()
_ = individualList.add(.artist(BlacklistedArtist(name: "B", match: .individual)))
expect(individualList.matches(track(artist: "A & B & C", names: ["A", "B", "C"])), "Real source arrays should match an individually blocked artist")
expect(individualList.matches(track(artist: "C & B & A", names: ["C", "B", "A"])), "Individual matches should not depend on the source array order")
expect(!individualList.matches(track(artist: "A&B&C")), "A combined artist string must never be split to find an individual")
expect(individualList.matches(track(artist: "B")), "An exact solo artist string can match an individual entry")
expect(track(artist: "A&B&C").artistNames.isEmpty, "Artist strings must not manufacture separate artist names")
expect(track(names: ["A", "a", "", "B"]).artistNames == ["A", "B"], "Genuine artist arrays should drop empty and duplicate choices")
expect(track(artist: "", names: ["A", "B"]).artistText == "A & B", "Separate artist data should remain usable even without a display string")
var accentList = BlacklistDocument()
_ = accentList.add(.artist(BlacklistedArtist(name: "Björk", match: .fullText)))
expect(!accentList.matches(track(artist: "Bjork")), "Accents must not be removed during exact matching")
expect(accentList.matches(track(artist: "BJO\u{0308}RK")), "Equivalent Unicode spellings and case should match")
var albumOnly = payload()
albumOnly.removeValue(forKey: "artist")
albumOnly["album"] = "B"
expect(!individualList.matches(MediaState(payload: albumOnly)), "An album fallback must never be blacklisted as an artist")

var songList = BlacklistDocument()
let blockedSong = BlacklistEntry.song(BlacklistedSong(title: "Song", artistText: "A&B&C"))
_ = songList.add(blockedSong)
expect(songList.matches(track()), "Songs must match title and full artist text together")
expect(!songList.matches(track(artist: "Other")), "The same title by a different artist must remain playable")
expect(!songList.matches(track("Song Remix")), "Song matches must not include suffixes or substring matches")
expect(!songList.add(.song(BlacklistedSong(title: " song ", artistText: "a&b&c"))), "Duplicate song entries should be ignored")
songList.remove(blockedSong)
expect(!songList.matches(track()), "Removing a song must stop its matching rule")
blocked.remove(fullGroup)
expect(blocked.artists.isEmpty, "An artist entry should be removable")
expect(!blocked.add(.artist(BlacklistedArtist(name: "  ", match: .fullText))), "Empty artist rules must not be saved")
expect(!blocked.add(.song(BlacklistedSong(title: "Song", artistText: ""))), "Songs without artist information must not be saved")

_ = blocked.add(fullGroup)
var skipping = AutoSkipState()
expect(skipping.observe(track("Current"), blacklist: blocked, enabled: true, now: 0) == .none, "Startup must leave an already-playing track alone")
expect(skipping.observe(track("Next"), blacklist: blocked, enabled: true, now: 1) == .skip, "A new blocked track should skip")
expect(skipping.observe(track("Next"), blacklist: blocked, enabled: true, now: 2) == .none, "The same track must not receive repeated skip commands")
var metadataUpdate = track("Next")
metadataUpdate.trackKey += "late-id"
expect(skipping.observe(metadataUpdate, blacklist: blocked, enabled: true, now: 3) == .none, "Metadata ID changes must not trigger another skip")
expect(skipping.observe(MediaState(), blacklist: blocked, enabled: true, now: 4) == .none, "Missing media should not skip")
expect(skipping.observe(track("Next"), blacklist: blocked, enabled: true, now: 5) == .none, "Reconnecting must not repeat a skip on the same track")
skipping.ignoreCurrent(track("Added now"))
expect(skipping.observe(track("Added now"), blacklist: blocked, enabled: true, now: 6) == .none, "Adding an entry must not skip the current track")
expect(skipping.observe(track("Paused", playing: false), blacklist: blocked, enabled: true, now: 7) == .none, "A paused selection should wait for playback")
expect(skipping.observe(track("Paused"), blacklist: blocked, enabled: true, now: 8) == .skip, "Starting a newly selected blocked track should skip")
expect(skipping.observe(track("Disabled"), blacklist: blocked, enabled: false, now: 9) == .none, "The toggle must disable automatic skipping")
expect(skipping.observe(track("Disabled"), blacklist: blocked, enabled: true, now: 10) == .none, "Enabling must not retroactively skip the current track")

var circuit = AutoSkipState()
_ = circuit.observe(MediaState(), blacklist: blocked, enabled: true, now: 0)
for index in 1...10 {
    expect(circuit.observe(track("Blocked \(index)"), blacklist: blocked, enabled: true, now: Double(index)) == .skip, "New blocked tracks may skip within the chain limit")
}
expect(circuit.observe(track("Blocked 11"), blacklist: blocked, enabled: true, now: 11) == .limitReached, "An all-blocked queue must stop issuing commands at the limit")
expect(circuit.limitReached, "The circuit limit must be visible to the menu")
_ = circuit.observe(track("Allowed", artist: "Other"), blacklist: blocked, enabled: true, now: 12)
expect(!circuit.limitReached, "An allowed track should reset the consecutive-skip limit")
expect(circuit.observe(track("Blocked again"), blacklist: blocked, enabled: true, now: 13) == .skip, "Filtering should recover after an allowed track")

let blacklistTestDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MediaHubBlacklistTests-\(UUID().uuidString)")
do {
    defer { try? FileManager.default.removeItem(at: blacklistTestDirectory) }
    let legacyURL = blacklistTestDirectory.appendingPathComponent("MediaBar/blacklist.json")
    let hubURL = blacklistTestDirectory.appendingPathComponent("MigratedMediaHub/blacklist.json")
    let legacyStore = BlacklistStore(fileURL: legacyURL)
    try legacyStore.add(fullGroup)
    try legacyStore.add(blockedSong)
    let legacyData = try Data(contentsOf: legacyURL)
    let migratedList = BlacklistStore(fileURL: hubURL, legacyFileURL: legacyURL)
    expect(migratedList.readError == nil && migratedList.document.contains(fullGroup) && migratedList.document.contains(blockedSong), "Renaming must migrate the complete blacklist")
    let migratedData = try Data(contentsOf: hubURL)
    expect(migratedData == legacyData, "Migration must preserve the exact original file contents")
    try migratedList.remove(fullGroup)
    migratedList.reload()
    expect(!migratedList.document.contains(fullGroup), "An existing MediaHub blacklist must not be replaced by the old file")
    let originalAfterMigration = try Data(contentsOf: legacyURL)
    expect(originalAfterMigration == legacyData, "The old blacklist must remain untouched")
    let absentURL = blacklistTestDirectory.appendingPathComponent("Absent/blacklist.json")
    let freshURL = blacklistTestDirectory.appendingPathComponent("FreshMediaHub/blacklist.json")
    let freshList = BlacklistStore(fileURL: freshURL, legacyFileURL: absentURL)
    expect(freshList.readError == nil && !FileManager.default.fileExists(atPath: freshURL.path), "A fresh install must not create an empty blacklist during migration")
    let badLegacyURL = blacklistTestDirectory.appendingPathComponent("invalid-legacy.json")
    let refusedURL = blacklistTestDirectory.appendingPathComponent("RefusedMediaHub/blacklist.json")
    try Data("invalid".utf8).write(to: badLegacyURL)
    expect(BlacklistStore(fileURL: refusedURL, legacyFileURL: badLegacyURL).readError != nil, "Malformed legacy data must report an error")
    expect(!FileManager.default.fileExists(atPath: refusedURL.path), "Malformed data must not be copied into the new location")
    try Data("{\"version\":2,\"artists\":[],\"songs\":[]}".utf8).write(to: badLegacyURL)
    expect(BlacklistStore(fileURL: refusedURL, legacyFileURL: badLegacyURL).readError != nil, "Unsupported legacy versions must not migrate")
    let blockedMigration = blacklistTestDirectory.appendingPathComponent("migration-obstruction")
    try Data("file".utf8).write(to: blockedMigration)
    expect(BlacklistStore(fileURL: blockedMigration.appendingPathComponent("blacklist.json"), legacyFileURL: legacyURL).readError != nil, "Migration write failures must be reported without discarding the old list")
    let url = blacklistTestDirectory.appendingPathComponent("MediaHub/blacklist.json")
    let store = BlacklistStore(fileURL: url)
    expect(store.readError == nil && store.document.artists.isEmpty, "A missing blacklist must load as empty")
    try store.add(fullGroup)
    try store.add(blockedSong)
    let reloaded = BlacklistStore(fileURL: url)
    expect(reloaded.document.contains(fullGroup) && reloaded.document.contains(blockedSong), "JSON must preserve artist and song entries across reloads")
    try reloaded.add(fullGroup)
    expect(reloaded.document.artists.count == 1, "Duplicate entries must not be written twice")
    try reloaded.remove(fullGroup)
    expect(!BlacklistStore(fileURL: url).document.contains(fullGroup), "Removal must persist to the JSON file")
    let malformed = Data("not valid json".utf8)
    try malformed.write(to: url)
    let corrupt = BlacklistStore(fileURL: url)
    expect(corrupt.readError != nil, "Malformed JSON must report a load error")
    var refusedOverwrite = false
    do { try corrupt.add(fullGroup) } catch { refusedOverwrite = true }
    expect(refusedOverwrite, "A corrupt document must not be overwritten by a new entry")
    let unchangedData = try Data(contentsOf: url)
    expect(unchangedData == malformed, "The original corrupt file must remain intact")
    try Data("{\"version\":2,\"artists\":[],\"songs\":[]}".utf8).write(to: url)
    expect(BlacklistStore(fileURL: url).readError != nil, "Future document versions must not be overwritten")
    try JSONEncoder().encode(BlacklistDocument()).write(to: url)
    corrupt.reload()
    expect(corrupt.readError == nil, "Fixing the JSON file and reloading should recover editing")
    let obstruction = blacklistTestDirectory.appendingPathComponent("obstructed")
    let unwritable = BlacklistStore(fileURL: obstruction.appendingPathComponent("blacklist.json"))
    try Data("file instead of directory".utf8).write(to: obstruction)
    var writeFailed = false
    do { try unwritable.add(fullGroup) } catch { writeFailed = true }
    expect(writeFailed && unwritable.document.artists.isEmpty, "A failed write must not add an unsaved in-memory entry")
} catch { fatalError("Blacklist persistence test failed: \(error)") }
expect(preferences.isEnabled(.autoSkip), "Automatic skipping should default to enabled")
preferences.setEnabled(false, for: .autoSkip)
expect(!FeaturePreferences(store: preferenceStore).isEnabled(.autoSkip), "The automatic skip toggle must persist")

expect(track().songBlacklistEntry == .song(BlacklistedSong(title: "Song", artistText: "A&B&C")), "The Touch Bar song action must target the title and full artist text")
expect(track().primaryArtistBlacklistEntry == .artist(BlacklistedArtist(name: "A&B&C", match: .fullText)), "The Touch Bar must not split a combined artist string")
expect(track(artist: "B & A", names: ["B", "A"]).primaryArtistBlacklistEntry == .artist(BlacklistedArtist(name: "B", match: .individual)), "The Touch Bar artist action must select the first real source artist")
expect(track(artist: "").primaryArtistBlacklistEntry == nil, "Missing artist metadata must disable the Touch Bar artist action")
expect(MediaState().songBlacklistEntry == nil, "No media must disable the Touch Bar song action")
var touchBarRules = BlacklistDocument()
let touchBarArtist = track().primaryArtistBlacklistEntry!
_ = touchBarRules.add(touchBarArtist)
expect(touchBarRules.contains(touchBarArtist), "The first Touch Bar blacklist action should add a rule")
touchBarRules.remove(touchBarArtist)
expect(!touchBarRules.contains(touchBarArtist), "The second Touch Bar blacklist action should remove the same rule")

print("Passed \(assertions) model assertions; no app or media service was launched.")
