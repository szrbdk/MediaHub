# MediaBar development rules

- Do not launch the application or test by opening a Touch Bar panel, window, or preview.
- Builds and logic tests that do not launch the application or access system media are allowed.
- Do not use Python to modify files.
- Do not create commits automatically. When the user requests a commit, use Conventional Commits.
- Keep all Touch Bar layout, styling, and visual interactions in `MediaBar/TouchBarView.swift`. Do not add media access or system panel presentation to this file.
- The menu bar menu must include the `MediaBar` heading; checked toggles for `Touch Bar`, `Notifications`, and `Automatic skipping`, in that order; `Add to blacklist`; `Manage blacklist`; the language submenu; and `Quit`. Save preferences in UserDefaults; all three feature toggles default to enabled. Do not add a main window, Dock icon, separate settings window, or automatic launch at login. A temporary notification panel that emerges near the camera without taking focus is allowed when the track changes.
- Save the blacklist atomically to `~/Library/Application Support/MediaBar/blacklist.json`. Adding an entry must not skip the current track; evaluate the filter when a new track starts playing. Do not split or reorder artist text. Offer individual artist choices only when the source provides a genuine artist array. Matching must preserve text except for case and leading/trailing whitespace. Prevent infinite skipping loops and repeated commands for the same track.
- Keep the menu bar icon tooltip set to `MediaBar`.
- Support English and Turkish. The language menu must offer only English and Turkish. On first launch, select and save the system's primary language, falling back to English if unsupported. Use the saved language on subsequent launches. Keep user-facing strings in localization resources under stable keys.
- Tapping the track title in the Touch Bar must open an action view rather than Music. This view contains a favorite button, track/artist information, and two blacklist buttons. Tapping the title again returns to the main view. Show the favorite button only in the action view. Blacklist buttons must toggle the same entry on and off. The artist button must use the first artist from a genuine array, or the complete artist text when no array is available.
- The implementation currently targets the user's existing Mac. Do not add publishing or distribution infrastructure unless requested.
- Prefer Swift, Objective-C, and C. Do not use Perl, shell, AppleScript, or Python scripts at runtime.
- Do not modify the reference TouchBar project at `/Users/sezerbudak/Developer/personal/TouchBar`.
