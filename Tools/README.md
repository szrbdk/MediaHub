# Release packaging

Packaging requires macOS and Xcode 27.1. The app itself does not need Xcode or these tools at runtime.

## Build a DMG

From the repository root:

```sh
xcrun swift -module-cache-path build/ModuleCache Tools/BuildRelease.swift
```

The tool builds Release for Apple Silicon and Intel, checks the app and embedded XPC service versions and signatures, stages the app beside an Applications shortcut, creates a compressed DMG, verifies its integrity, and generates a SHA-256 checksum. It never launches the application or its service.

The disk image has a 640 × 420 installation window with a Retina background, a drag arrow, and fixed app/Applications icon positions. The layout is generated directly in Swift; a small Objective-C helper creates the native background alias. No Finder automation, AppleScript, Python, or third-party packaging dependencies are used.

A temporary writable image is mounted without opening Finder, configured, detached, and converted to a compressed image. The layout generator checks its Finder metadata and resolves the background alias. A verified new image replaces the previous DMG only after successful conversion; its checksum is then regenerated. Temporary files stay under `build/Distribution`.

Output:

```text
dist/MediaHub-1.0.0.dmg
dist/MediaHub-1.0.0.dmg.sha256
```

The version is read from the built app. Update `MARKETING_VERSION` for both targets in the Xcode project before building another release. Keep the XPC Info.plist version substitutions in place. Build logs are written to `build/Distribution/release-build.log`. Build output and release packages are ignored by Git.

To recreate the DMG from an already-built and verified Release app:

```sh
xcrun swift -module-cache-path build/ModuleCache Tools/BuildRelease.swift --skip-build
```

The MIT license is included in the app resources and as a hidden file beside the app in the DMG, keeping the installation window focused on the two icons. The third-party BSD-3-Clause license remains in the app resources.

Packages are ad-hoc signed, not Developer ID signed or notarized. Keep that limitation explicit in the release notes and installation instructions.

## GitHub release

1. Commit and push the versioned source and documentation used to build the package.
2. Create a release in `szrbdk/MediaHub` with tag **v1.0.0**, targeting that commit, and title **MediaHub 1.0.0**.
3. Use `docs/releases/1.0.0.md` as the release description.
4. Upload the DMG and its `.sha256` file from `dist/`.
5. Publish after manually checking installation and the app on a compatible Mac.

The download link in the main README expects exactly the tag and DMG filename above. Creating or publishing a release is not performed by the packaging tool.
