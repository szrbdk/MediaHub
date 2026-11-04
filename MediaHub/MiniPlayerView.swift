import AppKit

private enum MiniPlayerStyle {
    static let artworkRadius: CGFloat = 9
    static let contentInset: CGFloat = 14
    // Concentric outer and inner corners: outer radius = inner radius + inset.
    static let panelRadius = artworkRadius + contentInset
    static let edgeTransition: CGFloat = 16
    static let artworkSize: CGFloat = 52
}

/// Screen-player layout and interactions, independent of Touch Bar presentation.
final class MiniPlayerView: NSView {
    var onAction: ((MediaAction) -> Void)?
    var onExpand: (() -> Void)?
    var onCollapse: (() -> Void)?
    private var state = MediaState()
    private var form: MiniPlayerState.Form = .expanded
    private var pose = MiniPlayerTransition.Pose.target(.hidden)
    private let surface = CAShapeLayer()
    private let surfaceMask = CAShapeLayer()
    private var artwork: Data?
    private var seekTrackKey: String?
    private let coverArea = MiniPlayerCover()
    private var cover: NSImageView { coverArea.imageView }
    private let title = NSTextField(labelWithString: "")
    private let artist = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let details = NSView()
    private let seek = MiniPlayerSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private var previous: NSButton!
    private var play: NSButton!
    private var next: NSButton!
    private var favorite: NSButton!
    private var expand: NSButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        surface.fillColor = NSColor(white: 0.025, alpha: 1).cgColor
        layer?.insertSublayer(surface, at: 0)
        layer?.mask = surfaceMask
        alphaValue = 0
        addSubview(details)
        cover.imageScaling = .scaleProportionallyUpOrDown
        cover.wantsLayer = true
        cover.layer?.cornerRadius = MiniPlayerStyle.artworkRadius
        cover.layer?.masksToBounds = true
        cover.setAccessibilityElement(false)
        coverArea.onCollapse = { [weak self] in self?.onCollapse?() }
        details.addSubview(coverArea)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .white
        artist.font = .systemFont(ofSize: 10)
        artist.textColor = NSColor(white: 0.62, alpha: 1)
        time.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        time.textColor = NSColor(white: 0.5, alpha: 1)
        time.alignment = .right
        for label in [title, artist, time] {
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            details.addSubview(label)
        }
        previous = button("backward.end.fill", action: #selector(goPrevious), parent: details)
        play = button("play.fill", action: #selector(togglePlayback), parent: details)
        next = button("forward.end.fill", action: #selector(goNext), parent: details)
        favorite = button("star", action: #selector(toggleFavorite), parent: details)
        expand = button("waveform", action: #selector(expandPlayer), parent: self)
        expand.contentTintColor = .systemPink
        seek.cell = MiniPlayerSliderCell()
        seek.minValue = 0
        seek.maxValue = 1
        seek.isContinuous = true
        seek.target = self
        seek.action = #selector(previewSeek)
        seek.onBegin = { [weak self] in self?.seekTrackKey = self?.state.trackKey }
        seek.onFinish = { [weak self] in
            guard let self, let key = self.seekTrackKey, key == self.state.trackKey else { return }
            self.seekTrackKey = nil
            self.onAction?(.seek(fraction: self.seek.doubleValue, trackKey: key))
        }
        details.addSubview(seek)
        render(state)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func button(_ symbol: String, action: Selector, parent: NSView) -> NSButton {
        let button = MiniPlayerButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!, target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.bezelStyle = .regularSquare
        parent.addSubview(button)
        return button
    }

    func setForm(_ form: MiniPlayerState.Form) {
        if self.form != form { cancelSeek() }
        // Keep the outgoing content's fixed layout while it fades away.
        if form == .expanded || form == .announcement { self.form = form }
        coverArea.collapseEnabled = form == .expanded && pose.wide >= 0.999
        render(state)
        needsLayout = true
        needsDisplay = true
    }

    func present(_ pose: MiniPlayerTransition.Pose) {
        guard self.pose.size != pose.size || self.pose.wide != pose.wide || self.pose.opacity != pose.opacity else { return }
        self.pose = pose
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        alphaValue = pose.opacity
        details.alphaValue = max(0, (pose.wide - 0.45) / 0.55)
        expand.alphaValue = max(0, 1 - pose.wide * 3)
        details.isHidden = pose.wide <= 0.001
        expand.isHidden = pose.wide >= 0.999
        coverArea.collapseEnabled = form == .expanded && pose.wide >= 0.999
        updateSurface()
        CATransaction.commit()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func containsSurface(_ point: NSPoint) -> Bool {
        pose.opacity > 0.01 && surfacePath().contains(point)
    }

    func cancelSeek() { seekTrackKey = nil }

    func render(_ state: MediaState) {
        if self.state.trackKey != state.trackKey || !state.timeline.isValid { cancelSeek() }
        self.state = state
        title.stringValue = state.hasMedia ? state.title : L("playback.waiting")
        artist.stringValue = state.hasMedia ? state.artist : ""
        title.toolTip = state.title
        artist.toolTip = state.artist
        if artwork != state.artworkData || cover.image == nil {
            artwork = state.artworkData
            cover.image = state.artworkData.flatMap(NSImage.init(data:)) ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            cover.contentTintColor = state.artworkData == nil ? .systemPink : nil
        }
        for button in [previous, play, next] { button?.isEnabled = state.hasMedia }
        configure(previous, symbol: state.isPodcast ? "gobackward.15" : "backward.end.fill",
                  key: state.isPodcast ? "playback.back_15_seconds" : "playback.previous")
        configure(play, symbol: state.playing ? "pause.fill" : "play.fill", key: "playback.toggle")
        configure(next, symbol: state.isPodcast ? "goforward.15" : "forward.end.fill",
                  key: state.isPodcast ? "playback.forward_15_seconds" : "playback.next")
        configure(favorite, symbol: state.favorite ? "star.fill" : "star", key: state.favorite ? "favorite.remove" : "favorite.add")
        favorite.isHidden = form != .expanded || !state.hasMedia || !state.isMusic
        favorite.isEnabled = !state.favoritePending && state.hasMedia && state.isMusic
        favorite.contentTintColor = state.favorite ? .systemPink : NSColor(white: 0.7, alpha: 1)
        favorite.setAccessibilityValue(L(state.favorite ? "favorite.active" : "favorite.inactive"))
        coverArea.updateLabel()
        for control in [previous!, play!, next!] { control.isHidden = form != .expanded }
        seek.isHidden = form != .expanded
        time.isHidden = form != .expanded
        configure(expand, symbol: "waveform", key: "mini.expand")
        expand.setAccessibilityValue(title.stringValue)
        seek.setAccessibilityLabel(L("touchbar.playback_position"))
        seek.isEnabled = state.hasMedia && state.timeline.isValid && !state.seekPending
        refreshTimeline()
    }

    private func configure(_ button: NSButton, symbol: String, key: String) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: L(key))
        button.toolTip = L(key)
        button.setAccessibilityLabel(L(key))
    }

    func refreshTimeline() {
        guard state.timeline.isValid else { time.stringValue = ""; seek.doubleValue = 0; return }
        let position: Double
        if seek.isDragging, seekTrackKey == state.trackKey { position = seek.doubleValue * state.timeline.duration }
        else {
            position = state.timeline.position(at: Date().timeIntervalSince1970)
            seek.doubleValue = position / state.timeline.duration
        }
        time.stringValue = "\(PlaybackTimeline.format(position)) / \(PlaybackTimeline.format(state.timeline.duration))"
        seek.setAccessibilityValue(PlaybackTimeline.format(position))
    }

    override func layout() {
        super.layout()
        details.frame = bounds
        let right = bounds.width - 14
        let announcing = form == .announcement
        let coverX = MiniPlayerStyle.edgeTransition + MiniPlayerStyle.contentInset
        let coverY = bounds.height - MiniPlayerStyle.edgeTransition - MiniPlayerStyle.contentInset - MiniPlayerStyle.artworkSize
        coverArea.frame = NSRect(x: coverX, y: coverY, width: MiniPlayerStyle.artworkSize, height: MiniPlayerStyle.artworkSize)
        let textX = coverArea.frame.maxX + 14
        title.frame = NSRect(x: textX, y: announcing ? 41 : 50,
                             width: max(20, right - textX - (announcing ? 0 : 32)), height: 16)
        artist.frame = NSRect(x: textX, y: announcing ? 24 : 35,
                              width: max(20, right - textX - (announcing ? 0 : 32)), height: 14)
        favorite.frame = NSRect(x: right - 26, y: 44, width: 26, height: 26)
        previous.frame = NSRect(x: textX - 2, y: 8, width: 26, height: 24)
        play.frame = NSRect(x: textX + 27, y: 8, width: 26, height: 24)
        next.frame = NSRect(x: textX + 56, y: 8, width: 26, height: 24)
        let seekX = textX + 94
        seek.frame = NSRect(x: seekX, y: 20, width: max(20, right - seekX), height: 14)
        time.frame = NSRect(x: seekX, y: 4, width: max(20, right - seekX), height: 12)
        let edge = surfaceEdge
        let body = NSRect(x: bounds.maxX - pose.size.width + edge, y: 0,
                          width: max(0, pose.size.width - edge), height: max(0, pose.size.height - edge))
        expand.frame = NSRect(x: body.midX - 18, y: body.midY - 18, width: 36, height: 36)
        updateSurface()
    }

    private var surfaceEdge: CGFloat { min(MiniPlayerStyle.edgeTransition, pose.size.width / 4, pose.size.height / 4) }

    private func surfacePath() -> CGPath {
        let w = bounds.maxX, h = pose.size.height, x = w - pose.size.width
        let edge = surfaceEdge
        let radius = max(0, min(MiniPlayerStyle.panelRadius, (pose.size.width - edge) / 2, (h - edge) / 2))
        let k: CGFloat = 0.55228475
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: 0))
        path.addCurve(to: CGPoint(x: x + edge, y: edge), control1: CGPoint(x: x + edge * k, y: 0), control2: CGPoint(x: x + edge, y: edge * (1 - k)))
        path.addLine(to: CGPoint(x: x + edge, y: h - edge - radius))
        path.addCurve(to: CGPoint(x: x + edge + radius, y: h - edge),
                      control1: CGPoint(x: x + edge, y: h - edge - radius * (1 - k)),
                      control2: CGPoint(x: x + edge + radius * (1 - k), y: h - edge))
        path.addLine(to: CGPoint(x: w - edge, y: h - edge))
        path.addCurve(to: CGPoint(x: w, y: h), control1: CGPoint(x: w - edge * (1 - k), y: h - edge), control2: CGPoint(x: w, y: h - edge * k))
        path.addLine(to: CGPoint(x: w, y: 0))
        path.closeSubpath()
        return path
    }

    private func updateSurface() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = surfacePath()
        surface.frame = bounds
        surfaceMask.frame = bounds
        surface.path = path
        surfaceMask.path = path
        CATransaction.commit()
    }

    @objc private func goPrevious() { onAction?(.previous) }
    @objc private func togglePlayback() { onAction?(.togglePlayback) }
    @objc private func goNext() { onAction?(.next) }
    @objc private func toggleFavorite() { onAction?(.toggleFavorite) }
    @objc private func previewSeek() { if seekTrackKey == state.trackKey { refreshTimeline() } }
    @objc private func expandPlayer() { onExpand?() }
}

private final class MiniPlayerCover: NSView {
    let imageView = NSImageView()
    var onCollapse: (() -> Void)?
    var collapseEnabled = true {
        didSet {
            if !collapseEnabled { hovering = false }
            updateHover()
        }
    }
    private var hovering = false
    private var tracking: NSTrackingArea?
    private let button = MiniPlayerButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(imageView)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: nil)
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        button.layer?.cornerRadius = MiniPlayerStyle.artworkRadius
        button.target = self
        button.action = #selector(collapse)
        button.isHidden = true
        addSubview(button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        imageView.frame = bounds
        button.frame = bounds
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        self.tracking = tracking
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; updateHover() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateHover() }
    private func updateHover() { button.isHidden = !collapseEnabled || !hovering }
    func updateLabel() {
        button.toolTip = L("mini.collapse")
        button.setAccessibilityLabel(L("mini.collapse"))
    }
    @objc private func collapse() { onCollapse?() }
}

private final class MiniPlayerButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class MiniPlayerSlider: NSSlider {
    var onBegin: (() -> Void)?
    var onFinish: (() -> Void)?
    private(set) var isDragging = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isDragging = true
        onBegin?()
        super.mouseDown(with: event)
        isDragging = false
        onFinish?()
    }
}

private final class MiniPlayerSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let knob = knobRect(flipped: flipped)
        let track = NSRect(x: rect.minX, y: knob.midY - 2, width: rect.width, height: 4)
        NSColor(white: 0.2, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        NSColor.systemPink.setFill()
        // AppKit reserves knob travel margins. Use its actual knob position
        // instead of deriving a second, differently inset position from value.
        let filledWidth = min(track.width, max(0, knob.midX - track.minX))
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: filledWidth, height: 4), xRadius: 2, yRadius: 2).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobRect.midX - 3.5, y: knobRect.midY - 3.5, width: 7, height: 7)).fill()
    }
}
