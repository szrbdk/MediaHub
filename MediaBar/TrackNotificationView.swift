import AppKit

/// Camera-aligned notification artwork and typography. No media access here.
final class TrackNotificationView: NSView {
    private let symbol = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let albumLabel = NSTextField(labelWithString: "")
    private var displayedArtwork: Data?
    private var hasArtwork = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        symbol.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 23, weight: .medium)
        symbol.contentTintColor = .systemPink
        symbol.imageScaling = .scaleProportionallyDown
        symbol.wantsLayer = true
        symbol.layer?.cornerRadius = 12
        symbol.layer?.masksToBounds = true
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        artistLabel.font = .systemFont(ofSize: 12, weight: .regular)
        artistLabel.textColor = NSColor(white: 0.72, alpha: 1)
        albumLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        albumLabel.textColor = NSColor(white: 0.46, alpha: 1)
        for label in [titleLabel, artistLabel, albumLabel] {
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.setAccessibilityElement(false)
            addSubview(label)
        }
        symbol.setAccessibilityElement(false)
        addSubview(symbol)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Şimdi çalıyor")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ announcement: TrackAnnouncement) {
        titleLabel.stringValue = announcement.title
        artistLabel.stringValue = announcement.artist
        artistLabel.isHidden = announcement.artist.isEmpty
        albumLabel.stringValue = announcement.album
        albumLabel.isHidden = announcement.album.isEmpty
        if displayedArtwork != announcement.artworkData {
            displayedArtwork = announcement.artworkData
            if let data = announcement.artworkData, let cover = NSImage(data: data) {
                hasArtwork = true
                symbol.symbolConfiguration = nil
                symbol.contentTintColor = nil
                symbol.image = cover
                symbol.imageScaling = .scaleProportionallyUpOrDown
            } else {
                hasArtwork = false
                symbol.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
                symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 23, weight: .medium)
                symbol.contentTintColor = .systemPink
                symbol.imageScaling = .scaleProportionallyDown
            }
        }
        setAccessibilityValue([announcement.title, announcement.artist, announcement.album].filter { !$0.isEmpty }.joined(separator: " — "))
        needsLayout = true
        needsDisplay = true
    }

    private var card: NSRect { NSRect(x: 12, y: 8, width: max(1, bounds.width - 24), height: 96) }
    private var coverFrame: NSRect { NSRect(x: card.minX + 16, y: card.midY - 32, width: 64, height: 64) }

    override func layout() {
        super.layout()
        symbol.frame = hasArtwork ? coverFrame : coverFrame.insetBy(dx: 16, dy: 16)
        let textX = coverFrame.maxX + 16
        let textWidth = max(1, card.maxX - textX - 20)
        var rows: [(NSTextField, CGFloat)] = [(titleLabel, 22)]
        if !artistLabel.isHidden { rows.append((artistLabel, 17)) }
        if !albumLabel.isHidden { rows.append((albumLabel, 15)) }
        let height = rows.reduce(CGFloat(0)) { $0 + $1.1 } + CGFloat(rows.count - 1) * 3
        var top = card.midY + height / 2
        for (label, height) in rows {
            label.frame = NSRect(x: textX, y: top - height, width: textWidth, height: height)
            top -= height + 3
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSColor(white: 0.045, alpha: 1)
        let body = NSBezierPath(roundedRect: card, xRadius: 25, yRadius: 25)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        background.setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        NSGradient(starting: NSColor(white: 0.035, alpha: 1), ending: NSColor(white: 0.095, alpha: 1))?
            .draw(in: card, angle: 90)
        // A restrained warm tint ties the cover area to the app's pink accent.
        NSGradient(starting: NSColor.systemPink.withAlphaComponent(0.055), ending: .clear)?
            .draw(in: NSRect(x: card.minX, y: card.minY, width: card.width * 0.6, height: card.height), angle: 0)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.1).setStroke()
        body.lineWidth = 0.5
        body.stroke()
        let coverShape = NSBezierPath(roundedRect: coverFrame, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        let coverShadow = NSShadow()
        coverShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        coverShadow.shadowBlurRadius = 6
        coverShadow.shadowOffset = NSSize(width: 0, height: -2)
        coverShadow.set()
        NSColor(white: 0.1, alpha: 1).setFill()
        coverShape.fill()
        NSGraphicsContext.restoreGraphicsState()
        if !hasArtwork {
            NSGradient(starting: NSColor.systemPink.withAlphaComponent(0.15),
                       ending: NSColor.systemPink.withAlphaComponent(0.04))?.draw(in: coverShape, angle: 90)
        }
        NSColor.white.withAlphaComponent(0.09).setStroke()
        coverShape.lineWidth = 0.5
        coverShape.stroke()
    }
}
