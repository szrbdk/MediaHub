// Packaging-only Finder layout. Does not launch Finder, MediaHub, or AppleScript.
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

struct LayoutError: Error, CustomStringConvertible {
    let description: String
}
func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw LayoutError(description: message) }
}
extension Data {
    mutating func u16(_ value: UInt16) { var v = value.bigEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
    mutating func u32(_ value: UInt32) { var v = value.bigEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
    mutating func ascii(_ value: String) { append(contentsOf: value.utf8) }
    mutating func utf16(_ value: String) { for unit in value.utf16 { u16(unit) } }
}

let width = 640
let height = 420
let iconY: UInt32 = 225
let iconPositions: [(String, UInt32)] = [("MediaHub.app", 180), ("Applications", 460)]

func background(at url: URL) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width * 2, height: height * 2, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw LayoutError(description: "Cannot create background context")
    }
    context.scaleBy(x: 2, y: 2)
    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [r, g, b, a])!
    }
    let gradient = CGGradient(colorsSpace: space,
        colors: [color(0.985, 0.98, 0.99), color(0.935, 0.945, 0.965)] as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
    func text(_ value: String, size: CGFloat, y: CGFloat, color: CGColor, bold: Bool = false) {
        let font = CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil)
        let string = NSAttributedString(string: value, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
        let line = CTLineCreateWithAttributedString(string)
        context.textPosition = CGPoint(x: (CGFloat(width) - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))) / 2, y: y)
        CTLineDraw(line, context)
    }
    text("MediaHub", size: 34, y: 340, color: color(0.12, 0.14, 0.19), bold: true)
    text("Drag MediaHub into Applications", size: 15, y: 310, color: color(0.38, 0.41, 0.48))
    for (_, x) in iconPositions {
        let rect = CGRect(x: CGFloat(x) - 76, y: CGFloat(height) - CGFloat(iconY) - 74, width: 152, height: 148)
        let path = CGPath(roundedRect: rect, cornerWidth: 30, cornerHeight: 30, transform: nil)
        context.addPath(path)
        context.setFillColor(color(1, 1, 1, 0.65))
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(color(0.2, 0.24, 0.32, 0.07))
        context.setLineWidth(1)
        context.strokePath()
    }
    context.setStrokeColor(color(0.96, 0.33, 0.56, 0.85))
    context.setLineWidth(3)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let center = CGFloat(height) - CGFloat(iconY)
    context.move(to: CGPoint(x: 294, y: center))
    context.addLine(to: CGPoint(x: 346, y: center))
    context.move(to: CGPoint(x: 336, y: center + 10))
    context.addLine(to: CGPoint(x: 346, y: center))
    context.addLine(to: CGPoint(x: 336, y: center - 10))
    context.strokePath()
    text("Open MediaHub from Applications after copying.", size: 12, y: 44, color: color(0.40, 0.43, 0.50))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw LayoutError(description: "Cannot encode background")
    }
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144,
        kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
    try check(CGImageDestinationFinalize(destination), "Cannot save background")
}

struct Record {
    let file: String
    let key: String
    let type: String
    let value: Data
    func encoded() -> Data {
        var data = Data()
        data.u32(UInt32(file.utf16.count)); data.utf16(file)
        data.ascii(key); data.ascii(type)
        if type == "blob" { data.u32(UInt32(value.count)) }
        data.append(value)
        return data
    }
}
func plist(_ dictionary: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
}

// One leaf is sufficient for this fixed installer layout. The buddy arena is
// partitioned completely, including the implicit 64-byte header reservation.
// Format reference: https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod
func store(backgroundAlias: Data) throws -> Data {
    let window: [String: Any] = ["WindowBounds": "{{240, 180}, {\(width), \(height)}}",
        "ShowSidebar": false, "ShowToolbar": false, "ShowStatusBar": false, "ShowPathbar": false,
        "ShowTabView": false, "SidebarWidth": 0]
    let icons: [String: Any] = ["viewOptionsVersion": 1, "backgroundType": 2,
        "backgroundImageAlias": backgroundAlias, "backgroundColorRed": 0.96,
        "backgroundColorGreen": 0.96, "backgroundColorBlue": 0.98,
        "iconSize": 96.0, "textSize": 13.0, "arrangeBy": "none", "labelOnBottom": true,
        "showItemInfo": false, "showIconPreview": true, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0, "gridSpacing": 100.0]
    var records = [
        Record(file: ".", key: "bwsp", type: "blob", value: try plist(window)),
        Record(file: ".", key: "icvp", type: "blob", value: try plist(icons)),
        Record(file: ".", key: "vSrn", type: "long", value: Data([0, 0, 0, 1])),
        Record(file: ".", key: "vstl", type: "type", value: Data("icnv".utf8))]
    for (name, x) in iconPositions {
        var location = Data()
        location.u32(x); location.u32(iconY); location.u32(0xffffffff); location.u32(0xffff0000)
        records.append(Record(file: name, key: "Iloc", type: "blob", value: location))
    }
    records.sort { a, b in
        let comparison = a.file.caseInsensitiveCompare(b.file)
        return comparison == .orderedSame ? a.key < b.key : comparison == .orderedAscending
    }
    var leaf = Data()
    leaf.u32(0); leaf.u32(UInt32(records.count))
    records.forEach { leaf.append($0.encoded()) }
    try check(leaf.count <= 4096, "Finder layout exceeds a single B-tree leaf")
    var master = Data()
    [UInt32(2), 0, UInt32(records.count), 1, 4096].forEach { master.u32($0) }
    var allocator = Data()
    allocator.u32(3); allocator.u32(0)
    [UInt32(2048 | 11), 64 | 5, 4096 | 12].forEach { allocator.u32($0) }
    allocator.append(Data(count: 253 * 4))
    allocator.u32(1); allocator.append(4); allocator.ascii("DSDB"); allocator.u32(1)
    for exponent in 0..<32 {
        let offset: UInt32? = exponent == 5 ? 96 : ((7...10).contains(exponent) || (13...30).contains(exponent)) ? UInt32(1) << exponent : nil
        allocator.u32(offset == nil ? 0 : 1)
        if let offset { allocator.u32(offset) }
    }
    try check(allocator.count <= 2048, "Invalid buddy allocator size")
    var result = Data(count: 8196)
    var header = Data()
    header.u32(1); header.ascii("Bud1"); header.u32(2048); header.u32(2048); header.u32(2048)
    header.append(Data(count: 16))
    for (offset, data) in [(0, header), (4 + 64, master), (4 + 2048, allocator), (4 + 4096, leaf)] {
        result.replaceSubrange(offset..<(offset + data.count), with: data)
    }
    return result
}

func verify(_ volume: URL) throws {
    let data = try Data(contentsOf: volume.appendingPathComponent(".DS_Store"))
    func integer(_ offset: Int) throws -> Int {
        try check(offset >= 0 && offset + 4 <= data.count, "Truncated Finder metadata")
        return data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }
    try check(data.count >= 36 && String(decoding: data[4..<8], as: UTF8.self) == "Bud1", "Invalid Finder store header")
    let allocator = try integer(8) + 4
    try check(try integer(8) == integer(16), "Inconsistent allocator offsets")
    func block(_ number: Int) throws -> Int { (try integer(allocator + 8 + number * 4) & ~31) + 4 }
    let master = try block(1)
    let leaf = try block(integer(master))
    try check(try integer(leaf) == 0 && integer(master + 12) == 1, "Expected one leaf")
    let count = try integer(leaf + 4)
    try check(count == 6 && count == integer(master + 8), "Unexpected Finder record count")
    var cursor = leaf + 8
    var found = [String: Data]()
    for _ in 0..<count {
        let units = try integer(cursor); cursor += 4
        try check(cursor + units * 2 + 8 <= data.count, "Invalid Finder record")
        let name = String(data: data[cursor..<(cursor + units * 2)], encoding: .utf16BigEndian) ?? ""
        cursor += units * 2
        let key = String(decoding: data[cursor..<(cursor + 4)], as: UTF8.self); cursor += 4
        let type = String(decoding: data[cursor..<(cursor + 4)], as: UTF8.self); cursor += 4
        let size = type == "blob" ? try integer(cursor) : 4
        if type == "blob" { cursor += 4 }
        try check(cursor + size <= data.count, "Truncated Finder value")
        found["\(name):\(key)"] = data.subdata(in: cursor..<(cursor + size)); cursor += size
    }
    for (name, x) in iconPositions {
        var expected = Data(); expected.u32(x); expected.u32(iconY)
        try check(found["\(name):Iloc"]?.prefix(8) == expected, "Incorrect icon position for \(name)")
    }
    guard let iconData = found[".:icvp"], let windowData = found[".:bwsp"],
          let icons = try PropertyListSerialization.propertyList(from: iconData, format: nil) as? [String: Any],
          let window = try PropertyListSerialization.propertyList(from: windowData, format: nil) as? [String: Any],
          let aliasData = icons["backgroundImageAlias"] as? Data else {
        throw LayoutError(description: "Missing Finder view settings")
    }
    try check(icons["iconSize"] as? Double == 96 && icons["backgroundType"] as? Int == 2, "Incorrect icon view settings")
    try check(window["ShowToolbar"] as? Bool == false && window["ShowSidebar"] as? Bool == false, "Unexpected Finder chrome")
    guard let bookmark = CFURLCreateBookmarkDataFromAliasRecord(nil, aliasData as CFData)?.takeRetainedValue() else {
        throw LayoutError(description: "Invalid background alias")
    }
    var stale = false
    let resolved = try URL(resolvingBookmarkData: bookmark as Data, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
    try check(resolved.standardizedFileURL == volume.appendingPathComponent(".background/install.jpg").standardizedFileURL, "Background alias points outside the disk image")
    guard let image = CGImageSourceCreateWithURL(resolved as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any] else {
        throw LayoutError(description: "Missing background image")
    }
    try check(properties[kCGImagePropertyPixelWidth as String] as? Int == width * 2 &&
        properties[kCGImagePropertyPixelHeight as String] as? Int == height * 2, "Incorrect Retina background dimensions")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    try check(arguments.count == 1 || (arguments.count == 2 && arguments[0] == "--verify"), "Usage: DMGLayout [--verify] <mounted-volume>")
    let volume = URL(fileURLWithPath: arguments.last!, isDirectory: true)
    if arguments.count == 1 {
        let directory = volume.appendingPathComponent(".background")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = directory.appendingPathComponent("install.jpg")
        try background(at: image)
        guard let reference = MHCreateDMGAlias(volume, image) else {
            throw LayoutError(description: "Cannot create Finder background alias")
        }
        try store(backgroundAlias: reference).write(to: volume.appendingPathComponent(".DS_Store"), options: .atomic)
        let license = volume.appendingPathComponent("LICENSE")
        if FileManager.default.fileExists(atPath: license.path) {
            var values = URLResourceValues(); values.isHidden = true
            var mutableURL = license
            try mutableURL.setResourceValues(values)
        }
    }
    try verify(volume)
    print("Verified Finder layout, icon positions, and Retina background alias. No application was launched.")
} catch {
    FileHandle.standardError.write(Data("DMG layout failed: \(error)\n".utf8))
    exit(1)
}
