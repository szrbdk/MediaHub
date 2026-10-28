# MediaHub

Previously named MediaBar. Open `MediaHub.xcodeproj` and use the `MediaHub` scheme. The application identifier is `com.sezerbudak.MediaHub`. On first launch, saved language and feature preferences are imported from `com.sezerbudak.MediaBar` without replacing existing MediaHub preferences. If the new blacklist is absent, a valid `~/Library/Application Support/MediaBar/blacklist.json` is copied atomically to `~/Library/Application Support/MediaHub/blacklist.json`. The original file remains unchanged. The new application identity may require granting Music automation permission again.

A native macOS Touch Bar media controller written in Swift/AppKit and Objective-C. The project builds with Xcode 27.1 and targets macOS 27.0. It currently targets the developer's Mac; compatibility with other systems has not been verified.

Launching the application enables the Touch Bar panel and track notifications according to saved preferences. The menu bar menu contains the **MediaHub** heading, **Touch Bar**, **Notifications**, and **Automatic skipping** toggles, **Add to blacklist**, **Manage blacklist**, a **Language** submenu, and **Quit**. Enabled features have checkmarks. Preferences are saved in UserDefaults and restored on the next launch; all three feature toggles default to enabled. The icon tooltip shows the application name. There is no main window, Dock icon, automatic launch at login, or separate settings window. Quitting closes the panels, sends any pending end-seek commands, and closes the XPC connection.

Disabling notifications immediately hides the visible card and cancels pending cards. Re-enabling them announces only subsequent track changes. Disabling the Touch Bar ends any active seek and restores the system's normal Touch Bar. Re-enabling it presents the panel again. These two settings are independent.

## Architecture

- `MediaHub/TouchBarView.swift`: All Touch Bar design, including dimensions, colors, buttons, scrolling text, progress drawing, and the expanded seek view. Make Touch Bar UI changes in this file.
- `MediaHub/MediaController.swift`: Media state, actions, timeline updates, and favorite requests. Communicates with the UI through `MediaState` and `MediaAction`.
- `MediaHub/TouchBarPresenter.swift` and `MediaHub/Native/TouchBarSystem.m`: System-wide Touch Bar presentation and application, desktop, and wake notifications.
- `MediaService`: An Objective-C XPC service that accesses MediaRemote directly. Xcode builds it and embeds it in the application's `Contents/XPCServices` directory. State is polled every 0.5 seconds; the displayed timeline advances locally between updates.
- `MediaHub/Native/MusicAutomation.m`: Sends Apple Events directly to Music without AppleScript, Perl, shell, or another interpreter. Reads favorite status every five seconds while idle and supports explicit add/remove requests.

In Podcasts, the previous/next controls skip backward/forward by 15 seconds. Holding a transport button starts seeking; releasing it, changing context, or reaching the 15-second safety limit ends seeking. Tapping the time area opens the expanded seek view. Releasing a drag submits the new position. Tapping the time area again returns to the normal view.

Tapping the track title opens the Touch Bar action view instead of Music, with this order: **favorite → track/artist information → song blacklist button → artist blacklist button**. Tapping the title again returns to the main view. The favorite button appears only in this view and only for Music. Tapping a blacklist button again removes the entry; blocked entries are indicated by pink coloring and text. The artist action uses the first name in a genuine artist array, or the complete, unsplit artist text if no array is available. Adding or removing an entry does not skip the current track. The action view closes when the track changes or the Touch Bar is disabled. Controls are disabled when no media is available; the time area is hidden when timeline information is unavailable.

## Favorites

The favorite star toggles immediately when tapped, without waiting for Music. Tapping a filled star removes the track from favorites. The button is disabled until the operation is confirmed or fails; additional taps are ignored and never queued. There is no fixed two-second cooldown. A fast confirmation makes the button available immediately, while a slow request keeps it disabled.

Late replies and stale reads do not override the optimistic star. If the write reply still contains the previous state, the button stays disabled while verification runs for up to five seconds. Failure or confirmation timeout silently restores the last confirmed state and re-enables the button, without an error notification or automatic retry. Track changes clear pending state and invalidate old callbacks, so the new track can be used immediately.

## Blacklist and automatic skipping

Use **Add to blacklist** to save the current song (title and artist text) or artist. Adding an entry does not skip the current track, so you can add multiple artists from the same song. Existing entries are checked and disabled. Selecting an entry in **Manage blacklist** removes it. If the track changes while the menu is open, the selected entry still refers to the track displayed in that menu.

Artist text is not split on `&`, commas, `feat.`, or similar markers. `A&B&C` matches only that text; it does not match `B&A&C` or `B` alone. Matching ignores case and leading/trailing whitespace while preserving internal whitespace, punctuation, and order. If the source provides the artist field as an actual array of names, each artist can be added separately. An individual artist entry matches that name in an array or an exactly matching solo artist string. The current MediaRemote source usually provides a single artist string. Names appear under **Song** and **Artists** section headings. Album names are never used as substitute artist information for matching.

The first addition creates the list atomically at `~/Library/Application Support/MediaHub/blacklist.json`:

```json
{
  "version": 1,
  "artists": [{ "name": "A&B&C", "match": "fullText" }],
  "songs": [{ "title": "Song title", "artistText": "A&B&C" }]
}
```

Individual artist entries use `individual` as their `match` value. The file is reloaded whenever the menu opens. Manual edits are loaded on the next application launch or menu opening. Malformed files and unsupported versions are not overwritten; the menu displays an error and automatic filtering is not applied. A write failure does not add an unsaved entry to the in-memory list.

The filter runs only when a new track starts playing. Starting the application with a track already playing, editing the list, or re-enabling automatic skipping does not skip the current track. A newly started blocked track receives a single next-track command, and its notification is suppressed. Failed commands are not retried repeatedly for the same track. At most 10 consecutive tracks are skipped. An allowed track, a gap longer than 30 seconds, or toggling the feature off and on resets this limit. Matching does not detect AI-generated music; it only applies the entries you save.

## Track notification panel

When a new track starts playing or playback is paused or resumed, a standalone dark card emerges from the top center of the screen, without a black strip connecting it to the screen edge. It displays the track title, artist, and album name when available. Artwork is shown when supplied by the player; otherwise, a waveform icon is used. A small play/pause badge indicates the playback state. There is no notification sound. The panel remains visible for about three seconds before retracting upward. It uses the active application's screen; on a notched display, text is positioned below the notch.

Artwork comes from MediaRemote's `artworkData` field and is not downloaded from the network. The XPC service uses ImageIO to produce a PNG thumbnail up to 160 pixels in size and caches it for the current track. Late artwork or album information updates the visible card without creating another notification or extending its display time.

`TrackNotificationPresenter.swift` uses an `NSPanel` that does not take focus or intercept clicks. Its window behaviors allow it to join all Spaces and other applications' full-screen spaces. The visual design lives in `TrackNotificationView.swift`. Actual full-screen behavior requires manual verification on the device.

The initial playback state at startup, repeated snapshots, and reconnecting to the same track without a playback change do not trigger duplicate announcements. Each observed pause or resume is announced once; transitions seen while notifications are disabled are not replayed when re-enabled. Rapid track changes show the latest track without accumulating a notification queue. Sleep, screen locking, and display layout changes dismiss the panel. The application does not request system notification permission or change Music's notification settings. To avoid duplicate notifications, you can disable Music notifications in System Settings.

## Native system access

Because of MediaRemote access checks introduced after macOS 15.4, the service identifier is set to `com.apple.sezerbudak.MediaHub.MediaService`. The main application identifier remains `com.sezerbudak.MediaHub`. This approach follows the [documented identity-check behavior in mediaremote-adapter](https://github.com/ungive/mediaremote-adapter#why-this-works). The service is built locally as part of this project; it is not supplied or signed by Apple.

Touch Bar presentation also uses private macOS APIs. Successful builds and package checks do not verify these APIs on a device. Missing symbols or connection failures are logged without crashing the application; media controls return to an empty or disabled state. There is no script-based fallback.

App Sandbox is disabled. Music favorites may require macOS automation permission on first use. The application bundle includes the usage description and Apple Events entitlement. The project does not include publishing, distribution, or launch-at-login infrastructure.

MediaRemote private API declarations were taken from revision `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd` of `ungive/mediaremote-adapter`. Its BSD-3-Clause license is preserved in `MediaHub/Resources/MediaRemoteAdapter-LICENSE.txt` and copied into the application bundle. The original TouchBar reference project is left unchanged.

## Verification without launching the application

Application icon PNG sizes and the monochrome menu bar vector PDF are stored in `Assets.xcassets`. Their Swift/CoreGraphics source is `Tools/GenerateIcons.swift`. Regenerate them with `xcrun swift -module-cache-path build/ModuleCache Tools/GenerateIcons.swift`; this does not launch the application.

```sh
xcodebuild -project MediaHub.xcodeproj -scheme MediaHub -configuration Debug -derivedDataPath build/Verification CODE_SIGN_IDENTITY=- build
xcodebuild -project MediaHub.xcodeproj -scheme MediaHub -configuration Release -derivedDataPath build/Verification CODE_SIGN_IDENTITY=- build

xcrun swiftc -module-cache-path build/ModuleCache MediaHub/Models/*.swift Tests/main.swift -o build/MediaHubModelTests
build/MediaHubModelTests
```

Model tests use Foundation. They do not launch MediaHub or its XPC service, create a Touch Bar, or access Music. They cover timeline and playback rates, invalid data, seek boundaries, player/track identity, stale favorite request results, blacklist matching and storage, automatic skipping safeguards, preferences, and language selection.

Physical Touch Bar appearance, media data from Music/Podcasts and other system players, automation permission, panel behavior after application changes or wake, and restoring the previous Touch Bar on Quit require manual verification. Do not launch the application or previews during automated development work.

## Language support

The language menu offers **English** and **Turkish**. On first launch, Turkish is selected when the system's primary language is Turkish; otherwise, English is selected. The choice is saved in UserDefaults. Subsequent launches use the saved language. Changes apply to menu and Touch Bar text without restarting the application. Translations live in `MediaHub/Resources/en.lproj` and `tr.lproj`, using stable keys such as `menu.language`. Track and artist names are not translated. macOS automation usage descriptions are also bundled in both languages; macOS determines the language of its system permission dialog.
