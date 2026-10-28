// Development-only packaging tool. Never launches MediaHub or its XPC service.
import Foundation
import CryptoKit

enum PackagingError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

let manager = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let build = root.appendingPathComponent("build/Distribution")
let output = root.appendingPathComponent("dist")
let app = build.appendingPathComponent("Build/Products/Release/MediaHub.app")

@discardableResult
func run(_ executable: String, _ arguments: [String], log: URL? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = root
    let pipe = Pipe()
    var handle: FileHandle?
    if let log {
        _ = manager.createFile(atPath: log.path, contents: nil)
        handle = try FileHandle(forWritingTo: log)
        process.standardOutput = handle
        process.standardError = handle
    } else {
        process.standardOutput = pipe
        process.standardError = pipe
    }
    try process.run()
    let data = log == nil ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    try handle?.close()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        let detail = try log.map { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").suffix(30).joined(separator: "\n") } ?? text
        throw PackagingError.invalid("\(executable) failed (\(process.terminationStatus)).\n\(detail)")
    }
    return text
}

func info(_ bundle: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
    guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw PackagingError.invalid("Invalid bundle: \(bundle.path)")
    }
    return dictionary
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw PackagingError.invalid(message) }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    try require(arguments.isEmpty || arguments == ["--skip-build"], "Usage: xcrun swift Tools/BuildRelease.swift [--skip-build]")
    try manager.createDirectory(at: build, withIntermediateDirectories: true)
    if arguments.isEmpty {
        print("Building Release for Apple Silicon and Intel…")
        try run("/usr/bin/xcrun", ["xcodebuild", "-project", "MediaHub.xcodeproj", "-scheme", "MediaHub",
            "-configuration", "Release", "-derivedDataPath", build.path, "ARCHS=arm64 x86_64",
            "ONLY_ACTIVE_ARCH=NO", "CODE_SIGN_IDENTITY=-", "build"], log: build.appendingPathComponent("release-build.log"))
    }
    let metadata = try info(app)
    guard let version = metadata["CFBundleShortVersionString"] as? String,
          version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
          let buildNumber = metadata["CFBundleVersion"] as? String else {
        throw PackagingError.invalid("The app must have a three-part release version and build number.")
    }
    let service = app.appendingPathComponent("Contents/XPCServices/MediaService.xpc")
    let serviceMetadata = try info(service)
    try require(metadata["CFBundleIdentifier"] as? String == "com.sezerbudak.MediaHub", "Unexpected app identifier")
    try require(serviceMetadata["CFBundleIdentifier"] as? String == "com.apple.sezerbudak.MediaHub.MediaService", "Unexpected XPC identifier")
    try require(serviceMetadata["CFBundleShortVersionString"] as? String == version &&
        serviceMetadata["CFBundleVersion"] as? String == buildNumber, "App and XPC versions must match")
    for executable in [app.appendingPathComponent("Contents/MacOS/MediaHub"), service.appendingPathComponent("Contents/MacOS/MediaService")] {
        let architectures = Set(try run("/usr/bin/lipo", ["-archs", executable.path]).split(whereSeparator: \.isWhitespace).map(String.init))
        try require(Set(["arm64", "x86_64"]).isSubset(of: architectures), "Missing architecture in \(executable.path)")
    }
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    for resource in ["en.lproj/Localizable.strings", "tr.lproj/Localizable.strings", "LICENSE", "MediaRemoteAdapter-LICENSE.txt"] {
        try require(manager.fileExists(atPath: app.appendingPathComponent("Contents/Resources/\(resource)").path), "Missing resource: \(resource)")
    }
    try manager.createDirectory(at: output, withIntermediateDirectories: true)
    let staging = build.appendingPathComponent("DMG-\(UUID().uuidString)")
    try manager.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: staging) }
    try run("/usr/bin/ditto", [app.path, staging.appendingPathComponent("MediaHub.app").path])
    try manager.copyItem(at: root.appendingPathComponent("LICENSE"), to: staging.appendingPathComponent("LICENSE"))
    try manager.createSymbolicLink(at: staging.appendingPathComponent("Applications"), withDestinationURL: URL(fileURLWithPath: "/Applications"))
    let aliasObject = build.appendingPathComponent("DMGAlias.o")
    let layoutTool = build.appendingPathComponent("DMGLayout")
    try run("/usr/bin/xcrun", ["clang", "-fobjc-arc", "-c", "Tools/DMGAlias.m", "-o", aliasObject.path],
        log: build.appendingPathComponent("dmg-alias-build.log"))
    try run("/usr/bin/xcrun", ["swiftc", "-module-cache-path", root.appendingPathComponent("build/ModuleCache").path,
        "-import-objc-header", "Tools/DMGAlias.h", "Tools/DMGLayout.swift", aliasObject.path,
        "-framework", "CoreServices", "-o", layoutTool.path], log: build.appendingPathComponent("dmg-layout-build.log"))
    let dmg = output.appendingPathComponent("MediaHub-\(version).dmg")
    let identifier = UUID().uuidString
    let writable = build.appendingPathComponent("Installer-\(identifier).dmg")
    let volume = build.appendingPathComponent("Installer-\(identifier)")
    let candidate = output.appendingPathComponent(".MediaHub-\(version)-\(identifier).dmg")
    try manager.createDirectory(at: volume, withIntermediateDirectories: true)
    var mounted = false
    defer {
        if mounted, (try? run("/usr/bin/hdiutil", ["detach", volume.path])) != nil { mounted = false }
        // Never recursively remove a mount point if detaching failed.
        if !mounted {
            try? manager.removeItem(at: volume)
            try? manager.removeItem(at: writable)
        }
        try? manager.removeItem(at: candidate)
    }
    print("Creating \(dmg.lastPathComponent)…")
    try run("/usr/bin/hdiutil", ["create", "-volname", "MediaHub \(version)", "-srcfolder", staging.path,
        "-format", "UDRW", "-fs", "HFS+", "-o", writable.path])
    try run("/usr/bin/hdiutil", ["attach", writable.path, "-readwrite", "-nobrowse", "-mountpoint", volume.path])
    mounted = true
    print("Configuring the drag-to-Applications window…")
    try run(layoutTool.path, [volume.path])
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", volume.appendingPathComponent("MediaHub.app").path])
    try run("/usr/bin/hdiutil", ["detach", volume.path])
    mounted = false
    try run("/usr/bin/hdiutil", ["convert", writable.path, "-format", "UDZO", "-o", candidate.path])
    try run("/usr/bin/hdiutil", ["verify", candidate.path])
    try run("/usr/bin/hdiutil", ["attach", candidate.path, "-readonly", "-nobrowse", "-mountpoint", volume.path])
    mounted = true
    try run(layoutTool.path, ["--verify", volume.path])
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", volume.appendingPathComponent("MediaHub.app").path])
    try run("/usr/bin/hdiutil", ["detach", volume.path])
    mounted = false
    if manager.fileExists(atPath: dmg.path) { _ = try manager.replaceItemAt(dmg, withItemAt: candidate) }
    else { try manager.moveItem(at: candidate, to: dmg) }
    let digest = SHA256.hash(data: try Data(contentsOf: dmg)).map { String(format: "%02x", $0) }.joined()
    try "\(digest)  \(dmg.lastPathComponent)\n".write(to: output.appendingPathComponent("\(dmg.lastPathComponent).sha256"), atomically: true, encoding: .utf8)
    print("Ready: \(dmg.path)\nSHA-256: \(digest)\nAd-hoc signed; not notarized. No application was launched.")
} catch {
    FileHandle.standardError.write(Data("Release packaging failed: \(error)\n".utf8))
    exit(1)
}
