// Development-only artwork generator. Does not launch MediaHub or create UI.
// Regenerate with: xcrun swift -module-cache-path build/ModuleCache Tools/GenerateIcons.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = project.appendingPathComponent("MediaHub/Assets.xcassets")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func gradient(_ context: CGContext, in path: CGPath, colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func drawAppIcon(_ context: CGContext) {
    let tile = rounded(CGRect(x: 96, y: 96, width: 832, height: 832), radius: 188)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0, 0, 0, 0.3))
    context.addPath(tile)
    context.setFillColor(color(0.06, 0.065, 0.085))
    context.fillPath()
    context.restoreGState()
    gradient(context, in: tile, colors: [color(0.055, 0.06, 0.08), color(0.16, 0.17, 0.21)],
             from: CGPoint(x: 512, y: 96), to: CGPoint(x: 512, y: 928))
    context.addPath(tile)
    context.setStrokeColor(color(1, 1, 1, 0.1))
    context.setLineWidth(2)
    context.strokePath()

    // A wide Touch Bar capsule containing the shared five-bar audio mark.
    let capsule = rounded(CGRect(x: 172, y: 378, width: 680, height: 268), radius: 68)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0, 0, 0, 0.45))
    context.addPath(capsule)
    context.setFillColor(color(0.06, 0.055, 0.075))
    context.fillPath()
    context.restoreGState()
    gradient(context, in: capsule, colors: [color(0.065, 0.06, 0.085), color(0.16, 0.145, 0.185)],
             from: CGPoint(x: 512, y: 378), to: CGPoint(x: 512, y: 646))
    context.addPath(capsule)
    context.setStrokeColor(color(0.43, 0.4, 0.48, 0.7))
    context.setLineWidth(4)
    context.strokePath()

    for (index, height) in [66.0, 118, 180, 118, 66].enumerated() {
        let rect = CGRect(x: 369 + CGFloat(index) * 62, y: 512 - height / 2, width: 38, height: height)
        gradient(context, in: rounded(rect, radius: 19), colors: [color(1, 0.16, 0.36), color(1, 0.43, 0.65)],
                 from: CGPoint(x: 512, y: 422), to: CGPoint(x: 512, y: 602))
    }
}

func writeAppIcon(pixels: Int, filename: String) throws {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.setShouldAntialias(true)
    drawAppIcon(context)
    let image = context.makeImage()!
    let destinationURL = assets.appendingPathComponent("AppIcon.appiconset/\(filename)")
    let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

for size in [16, 32, 128, 256, 512] {
    try writeAppIcon(pixels: size, filename: "icon_\(size)x\(size).png")
    try writeAppIcon(pixels: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}

let menuDirectory = assets.appendingPathComponent("MenuBarIcon.imageset")
try FileManager.default.createDirectory(at: menuDirectory, withIntermediateDirectories: true)
let consumer = CGDataConsumer(url: menuDirectory.appendingPathComponent("MenuBarIcon.pdf") as CFURL)!
var mediaBox = CGRect(x: 0, y: 0, width: 18, height: 18)
let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
pdf.beginPDFPage(nil)
pdf.setStrokeColor(color(0, 0, 0))
pdf.setFillColor(color(0, 0, 0))
pdf.setLineWidth(1.25)
pdf.addPath(rounded(CGRect(x: 0.75, y: 3.5, width: 16.5, height: 11), radius: 3.25))
pdf.strokePath()
for (index, height) in [3.0, 5, 7, 5, 3].enumerated() {
    pdf.addPath(rounded(CGRect(x: 3.375 + CGFloat(index) * 2.5, y: 9 - height / 2, width: 1.25, height: height), radius: 0.625))
    pdf.fillPath()
}
pdf.endPDFPage()
pdf.closePDF()
print("Generated 10 app icon PNGs and the template menu icon PDF.")
