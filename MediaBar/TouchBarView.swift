import AppKit
import QuartzCore

/// All Touch Bar layout, drawing and direct-touch interactions live here.
/// Media access and system-wide presentation belong to the controller.
final class TouchBarView: NSObject {
    let bar = NSTouchBar()
    var onAction: ((MediaAction) -> Void)?
    private var state = MediaState()
    private var presented = false
    private var scrubOpen = false
    private var scrubTrackKey = ""
    private let titleLabel = MarqueeLabel(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let progressView = TrackProgressView()
    private let seekSurface = SeekSurface(frame: .zero)
    private let seekLabel = NSTextField(labelWithString: "")
    private var backButton: NSButton!
    private var playButton: NSButton!
    private var nextButton: NSButton!
    private var favoriteButton: NSButton!
    private var normalControls: NSView!
    private var normalTrailing: NSView!
    private var leftSlot: LayoutReportingStack!
    private var rightSlot: LayoutReportingStack!
    private var expandedTime: NSView!
    private var timelineView: NSView!
    private var songInfoView: NSView!
    private var songWidth: NSLayoutConstraint!
    private var songSizingWork: DispatchWorkItem?

    override init() {
        super.init()
        normalControls = makeControls()
        leftSlot = LayoutReportingStack(views: [normalControls])
        leftSlot.onLayout = { [weak self] in self?.scheduleSongSizing() }
        leftSlot.spacing = 0
        leftSlot.alignment = .centerY
        leftSlot.detachesHiddenViews = true
        let controls = NSCustomTouchBarItem(identifier: .init("com.sezerbudak.MediaBar.controls"))
        controls.view = leftSlot

        let escape = NSCustomTouchBarItem(identifier: .init("com.sezerbudak.MediaBar.emptyEscape"))
        let spacer = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 30))
        spacer.widthAnchor.constraint(equalToConstant: 1).isActive = true
        escape.view = spacer

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = NSColor(white: 0.62, alpha: 1)
        timeLabel.alignment = .center
        let timelineStack = NSView()
        timelineStack.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        timelineStack.addSubview(timeLabel)
        timelineStack.addSubview(progressView)
        let tap = NSClickGestureRecognizer(target: self, action: #selector(toggleScrubber(_:)))
        tap.allowedTouchTypes = .direct
        timelineStack.addGestureRecognizer(tap)
        timelineStack.toolTip = "Sarma çubuğunu açmak için dokunun"
        NSLayoutConstraint.activate([
            timelineStack.widthAnchor.constraint(equalToConstant: 112),
            timelineStack.heightAnchor.constraint(equalToConstant: 28),
            timeLabel.topAnchor.constraint(equalTo: timelineStack.topAnchor, constant: 1),
            timeLabel.leadingAnchor.constraint(equalTo: timelineStack.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: timelineStack.trailingAnchor),
            timeLabel.heightAnchor.constraint(equalToConstant: 16),
            progressView.leadingAnchor.constraint(equalTo: timelineStack.leadingAnchor, constant: 2),
            progressView.trailingAnchor.constraint(equalTo: timelineStack.trailingAnchor, constant: -2),
            progressView.bottomAnchor.constraint(equalTo: timelineStack.bottomAnchor, constant: -4),
            progressView.heightAnchor.constraint(equalToConstant: 3)
        ])
        progressView.setAccessibilityLabel("Oynatma ilerlemesi")
        timelineView = timelineStack
        let trailing = NSStackView(views: [favoriteButton, timelineStack])
        trailing.spacing = 7
        trailing.alignment = .centerY
        normalTrailing = trailing
        rightSlot = LayoutReportingStack(views: [trailing])
        rightSlot.onLayout = { [weak self] in self?.scheduleSongSizing() }
        rightSlot.spacing = 0
        rightSlot.alignment = .centerY
        rightSlot.detachesHiddenViews = true
        let timelineItem = NSCustomTouchBarItem(identifier: .init("com.sezerbudak.MediaBar.timeline"))
        timelineItem.visibilityPriority = .high
        timelineItem.view = rightSlot
        bar.templateItems = [controls, escape, timelineItem]
        bar.escapeKeyReplacementItemIdentifier = escape.identifier
        bar.defaultItemIdentifiers = [controls.identifier, .flexibleSpace, timelineItem.identifier]
        makeScrubBar()
        render(MediaState())
    }

    private func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let button = HoldMediaButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        button.bezelStyle = .rounded
        button.isBordered = true
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(equalToConstant: 48).isActive = true
        button.toolTip = label
        return button
    }

    private func makeControls() -> NSView {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        let text = NSStackView(views: [titleLabel])
        text.orientation = .horizontal
        text.alignment = .centerY
        text.spacing = 0
        text.distribution = .fill
        songInfoView = text
        songWidth = text.widthAnchor.constraint(equalToConstant: 250)
        songWidth.priority = NSLayoutConstraint.Priority(999)
        songWidth.isActive = true
        text.heightAnchor.constraint(equalToConstant: 28).isActive = true
        text.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        text.wantsLayer = true
        text.layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        text.layer?.cornerRadius = 7
        text.layer?.borderWidth = 0
        text.layer?.borderColor = NSColor(white: 0.19, alpha: 1).cgColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalTo: text.widthAnchor, constant: -20).isActive = true
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        backButton = button("backward.end.fill", "Önceki", #selector(previous))
        playButton = button("play.fill", "Oynat / duraklat", #selector(toggle))
        nextButton = button("forward.end.fill", "Sonraki", #selector(next))
        for (control, forward) in [(backButton!, false), (nextButton!, true)] {
            guard let hold = control as? HoldMediaButton else { continue }
            hold.configureHold()
            hold.onHold = { [weak self] began in
                self?.onAction?(began ? .beginSeeking(forward: forward) : .endSeeking)
            }
        }
        let openPlayer = NSClickGestureRecognizer(target: self, action: #selector(openPlayer))
        openPlayer.allowedTouchTypes = .direct
        text.addGestureRecognizer(openPlayer)
        favoriteButton = button("star", "Favorilere ekle", #selector(addFavorite))
        let stack = NSStackView(views: [backButton, playButton, nextButton, text])
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.distribution = .fill
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        return stack
    }

    private func makeScrubBar() {
        seekSurface.widthAnchor.constraint(equalToConstant: 480).isActive = true
        seekSurface.heightAnchor.constraint(equalToConstant: 30).isActive = true
        seekSurface.onPreview = { [weak self] fraction in
            guard let self, self.scrubTrackKey == self.state.trackKey else { return }
            self.seekLabel.stringValue = self.timeText(fraction * self.state.timeline.duration)
        }
        seekSurface.onCommit = { [weak self] fraction in
            guard let self, self.scrubOpen, self.state.timeline.isValid,
                  self.scrubTrackKey == self.state.trackKey else { return }
            self.onAction?(.seek(fraction: fraction, trackKey: self.scrubTrackKey))
        }
        seekSurface.onCancel = { [weak self] in self?.refreshProgress() }
        seekSurface.isHidden = true
        leftSlot.addArrangedSubview(seekSurface)
        seekLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        seekLabel.textColor = NSColor(white: 0.62, alpha: 1)
        seekLabel.alignment = .center
        let target = NSView()
        seekLabel.translatesAutoresizingMaskIntoConstraints = false
        target.addSubview(seekLabel)
        NSLayoutConstraint.activate([
            target.widthAnchor.constraint(equalToConstant: 112),
            target.heightAnchor.constraint(equalToConstant: 28),
            seekLabel.topAnchor.constraint(equalTo: target.topAnchor, constant: 1),
            seekLabel.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            seekLabel.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            seekLabel.heightAnchor.constraint(equalToConstant: 16)
        ])
        let tap = NSClickGestureRecognizer(target: self, action: #selector(toggleScrubber(_:)))
        tap.allowedTouchTypes = .direct
        target.addGestureRecognizer(tap)
        target.toolTip = "Normal görünüme dönmek için dokunun"
        expandedTime = target
        target.isHidden = true
        rightSlot.addArrangedSubview(target)
    }

    func render(_ newState: MediaState) {
        let animateTitleChange = state.hasMedia && newState.hasMedia && newState.trackKey != state.trackKey
        if newState.trackKey != state.trackKey || !newState.timeline.isValid { closeScrubber() }
        state = newState
        [backButton, playButton, nextButton].forEach { $0?.isEnabled = state.hasMedia }
        playButton.image = NSImage(systemSymbolName: state.playing ? "pause.fill" : "play.fill", accessibilityDescription: "Oynat / duraklat")
        backButton.image = NSImage(systemSymbolName: state.isPodcast ? "gobackward.15" : "backward.end.fill", accessibilityDescription: state.isPodcast ? "15 saniye geri" : "Önceki")
        nextButton.image = NSImage(systemSymbolName: state.isPodcast ? "goforward.15" : "forward.end.fill", accessibilityDescription: state.isPodcast ? "15 saniye ileri" : "Sonraki")
        favoriteButton.isHidden = !state.hasMedia || !state.isMusic
        favoriteButton.isEnabled = state.hasMedia && state.isMusic && !state.favoritePending
        favoriteButton.image = NSImage(systemSymbolName: state.favorite ? "star.fill" : "star", accessibilityDescription: state.favorite ? "Favorilere eklendi" : "Favorilere ekle")
        favoriteButton.toolTip = state.favoritePending ? "Music’ten onay bekleniyor" : state.favorite ? "Favorilerde" : "Favorilere ekle"
        renderTitle(animateChange: animateTitleChange)
        refreshProgress()
        scheduleSongSizing()
    }

    private func renderTitle(animateChange: Bool) {
        guard state.hasMedia else {
            titleLabel.cancelTransition()
            titleLabel.attributedStringValue = NSAttributedString(string: "♫  Çalan içerik bekleniyor", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 0.55, alpha: 1)])
            titleLabel.toolTip = "Çalan içerik bekleniyor"
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let value = NSMutableAttributedString(string: state.isPodcast ? "◉  " : "♫  ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: state.playing ? NSColor.systemPink : NSColor(white: 0.5, alpha: 1)])
        value.append(NSAttributedString(string: state.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]))
        if !state.artist.isEmpty {
            value.append(NSAttributedString(string: "   ·   ", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 0.35, alpha: 1)]))
            value.append(NSAttributedString(string: state.artist, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 0.66, alpha: 1)]))
        }
        value.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: value.length))
        titleLabel.setText(value, animateChange: animateChange)
        titleLabel.toolTip = state.artist.isEmpty ? state.title : "\(state.title) — \(state.artist)"
    }

    func refreshProgress() {
        timelineView.isHidden = !state.timeline.isValid
        guard state.timeline.isValid else { return }
        let position = state.timeline.position(at: Date().timeIntervalSince1970)
        progressView.fraction = position / state.timeline.duration
        let text = timeText(position)
        timeLabel.stringValue = text
        progressView.setAccessibilityValue(text)
        if scrubOpen && !seekSurface.isDragging {
            seekSurface.fraction = position / state.timeline.duration
            seekLabel.stringValue = text
        }
    }

    private func timeText(_ position: Double) -> String {
        "\(PlaybackTimeline.format(position)) / \(PlaybackTimeline.format(state.timeline.duration))"
    }

    @objc private func toggleScrubber(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        if scrubOpen { closeScrubber(); return }
        guard state.timeline.isValid else { return }
        onAction?(.endSeeking)
        scrubTrackKey = state.trackKey
        scrubOpen = true
        refreshProgress()
        updateModeViews()
    }

    private func closeScrubber() {
        guard scrubOpen else { return }
        scrubOpen = false
        seekSurface.cancelInteraction()
        updateModeViews()
    }

    private func updateModeViews() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            normalControls.isHidden = scrubOpen
            normalTrailing.isHidden = scrubOpen
            seekSurface.isHidden = !scrubOpen
            expandedTime.isHidden = !scrubOpen
            leftSlot.layoutSubtreeIfNeeded()
            rightSlot.layoutSubtreeIfNeeded()
            CATransaction.commit()
        }
        titleLabel.animationsEnabled = presented && !scrubOpen
        scheduleSongSizing()
    }

    func setPresented(_ visible: Bool) {
        presented = visible
        titleLabel.animationsEnabled = visible && !scrubOpen
        scheduleSongSizing()
    }

    private func scheduleSongSizing() {
        guard !scrubOpen, presented else { return }
        songSizingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.scrubOpen, self.presented, let window = self.leftSlot.window,
                  window === self.rightSlot.window else { return }
            let left = self.leftSlot.convert(self.leftSlot.bounds, to: nil)
            let navigationWidth = self.normalControls.bounds.width - self.songInfoView.bounds.width
            let availableWidth = window.contentView?.bounds.width ?? window.frame.width
            let reservedTrailingWidth = max(167, self.rightSlot.fittingSize.width)
            let width = min(320, max(100, availableWidth - left.minX - navigationWidth - reservedTrailingWidth - 24))
            guard width.isFinite, abs(self.songWidth.constant - width) > 0.5 else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                self.songWidth.constant = width
                self.songInfoView.invalidateIntrinsicContentSize()
                self.normalControls.invalidateIntrinsicContentSize()
                self.leftSlot.invalidateIntrinsicContentSize()
                self.leftSlot.layoutSubtreeIfNeeded()
            }
        }
        songSizingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func stop() {
        songSizingWork?.cancel()
        closeScrubber()
        setPresented(false)
        onAction = nil
    }

    @objc private func toggle() { onAction?(.togglePlayback) }
    @objc private func previous() { onAction?(.previous) }
    @objc private func next() { onAction?(.next) }
    @objc private func openPlayer() { onAction?(.openPlayer) }
    @objc private func addFavorite() { onAction?(.addFavorite) }
}

private final class TrackProgressView: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 80, height: 28) }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: (bounds.height - 3) / 2, width: bounds.width, height: 3)
        NSColor(white: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        guard fraction > 0 else { return }
        NSColor.systemPink.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * min(1, max(0, fraction)), height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    }
}
import AppKit
import QuartzCore

final class LayoutReportingStack: NSStackView {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// Only overflowing labels animate. Short labels keep their original intrinsic size.
final class MarqueeLabel: NSTextField {
    var animationsEnabled = false { didSet { updateAnimation() } }
    private var animationTimer: Timer?
    private var beganAt = CACurrentMediaTime()
    private var offset: CGFloat = 0
    private var lastWidth: CGFloat = 0
    // Faster than the normal 22 pt/s marquee. Both panels move together.
    private let transitionDuration: Double = 0.35
    private var outgoingImage: NSImage?
    private var transitionBeganAt: Double = 0

    func setText(_ text: NSAttributedString, animateChange: Bool) {
        var snapshot: NSImage?
        if animateChange, animationsEnabled, bounds.width > 0, bounds.height > 0,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            // Capture the visible marquee position (or an interrupted slide),
            // rather than restarting the outgoing text at its beginning.
            cacheDisplay(in: bounds, to: bitmap)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(bitmap)
            snapshot = image
        }
        attributedStringValue = text
        if let snapshot {
            outgoingImage = snapshot
            transitionBeganAt = CACurrentMediaTime()
            offset = 0
            updateAnimation()
        }
    }

    func cancelTransition() {
        outgoingImage = nil
        beganAt = CACurrentMediaTime()
        offset = 0
    }

    override var attributedStringValue: NSAttributedString {
        get { super.attributedStringValue }
        set {
            guard !super.attributedStringValue.isEqual(to: newValue) else { return }
            super.attributedStringValue = newValue
            beganAt = CACurrentMediaTime()
            offset = 0
            updateAnimation()
            needsDisplay = true
        }
    }

    private var overflow: CGFloat { max(0, attributedStringValue.size().width - max(1, bounds.width)) }
    override func layout() {
        super.layout()
        if abs(lastWidth - bounds.width) > 0.5 {
            lastWidth = bounds.width
            updateAnimation()
        }
    }
    private func updateAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard animationsEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            cancelTransition()
            offset = 0
            needsDisplay = true
            return
        }
        guard outgoingImage != nil || overflow > 0 else { needsDisplay = true; return }
        let timer = Timer(timeInterval: outgoingImage == nil ? 1.0 / 30 : 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.outgoingImage != nil {
                if CACurrentMediaTime() - self.transitionBeganAt >= self.transitionDuration {
                    self.cancelTransition()
                    self.updateAnimation()
                }
                self.needsDisplay = true
                return
            }
            let distance = max(0, self.attributedStringValue.size().width - self.bounds.width + 4)
            let travel = Double(distance) / 22
            let cycle = 2 + travel + 1.5 + travel
            let phase = (CACurrentMediaTime() - self.beganAt).truncatingRemainder(dividingBy: cycle)
            if phase < 2 { self.offset = 0 }
            else if phase < 2 + travel { self.offset = CGFloat((phase - 2) * 22) }
            else if phase < 3.5 + travel { self.offset = distance }
            else { self.offset = max(0, distance - CGFloat((phase - 3.5 - travel) * 22)) }
            self.needsDisplay = true
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    override func draw(_ dirtyRect: NSRect) {
        if let outgoingImage, animationsEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let phase = min(1, max(0, (CACurrentMediaTime() - transitionBeganAt) / transitionDuration))
            let eased = CGFloat(phase * phase * (3 - 2 * phase))
            NSGraphicsContext.saveGraphicsState()
            bounds.clip()
            outgoingImage.draw(in: bounds.offsetBy(dx: -bounds.width * eased, dy: 0),
                               from: .zero, operation: .sourceOver, fraction: 1,
                               respectFlipped: true, hints: nil)
            // Let NSTextField draw the incoming panel exactly as it will look
            // at rest, including its normal truncation and baseline.
            NSGraphicsContext.saveGraphicsState()
            let translation = NSAffineTransform()
            translation.translateX(by: bounds.width * (1 - eased), yBy: 0)
            translation.concat()
            bounds.clip()
            super.draw(bounds)
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        guard overflow > 0, animationsEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            super.draw(dirtyRect)
            return
        }
        let text = NSMutableAttributedString(attributedString: attributedStringValue)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        NSGraphicsContext.saveGraphicsState()
        bounds.clip()
        let size = text.size()
        text.draw(in: NSRect(x: 2 - offset, y: (bounds.height - size.height) / 2, width: size.width + 4, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
    }

    deinit { animationTimer?.invalidate() }
}

/// A large direct-touch target for the expanded seek screen. Dragging previews;
/// only releasing a successful gesture sends a seek command.
final class SeekSurface: NSView, NSGestureRecognizerDelegate {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var onPreview: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?
    var onCancel: (() -> Void)?
    var isDragging = false
    private var pan: NSPanGestureRecognizer!

    func cancelInteraction() {
        isDragging = false
        // Reset recognizers so a gesture from the previous track cannot commit.
        gestureRecognizers.forEach { $0.isEnabled = false; $0.isEnabled = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        pan = NSPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.allowedTouchTypes = .direct
        addGestureRecognizer(pan)
        let click = NSClickGestureRecognizer(target: self, action: #selector(tap(_:)))
        click.allowedTouchTypes = .direct
        click.delegate = self
        addGestureRecognizer(click)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Oynatma konumu")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func value(_ recognizer: NSGestureRecognizer) -> Double {
        min(1, max(0, Double((recognizer.location(in: self).x - 8) / max(1, bounds.width - 16))))
    }
    @objc private func drag(_ recognizer: NSPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            isDragging = true
            fraction = value(recognizer)
            onPreview?(fraction)
        case .ended:
            isDragging = false
            fraction = value(recognizer)
            onCommit?(fraction)
        case .cancelled:
            isDragging = false
            onCancel?()
        default: break
        }
    }
    @objc private func tap(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        fraction = value(recognizer)
        onCommit?(fraction)
    }
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        otherGestureRecognizer === pan
    }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 8, y: bounds.midY - 3, width: max(1, bounds.width - 16), height: 6)
        NSColor(white: 0.2, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        let x = track.minX + track.width * min(1, max(0, fraction))
        NSColor.systemPink.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: x - track.minX, height: 6), xRadius: 3, yRadius: 3).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 6, y: bounds.midY - 6, width: 12, height: 12)).fill()
    }
}

/// Delays the normal button action until the press recognizer fails, so holding
/// never also triggers the previous/next action.
final class HoldMediaButton: NSButton {
    var onHold: ((Bool) -> Void)?
    private var holding = false
    func configureHold() {
        let press = NSPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0.55
        press.allowedTouchTypes = .direct
        press.delaysPrimaryMouseButtonEvents = true
        addGestureRecognizer(press)
    }
    @objc private func pressed(_ press: NSPressGestureRecognizer) {
        if press.state == .began {
            holding = true
            onHold?(true)
        } else if press.state == .ended || press.state == .cancelled {
            onHold?(false)
            DispatchQueue.main.async { [weak self] in self?.holding = false }
        }
    }
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        guard !holding else { return false }
        return super.sendAction(action, to: target)
    }
}
