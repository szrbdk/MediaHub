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
    private var detailsOpen = false
    private let detailsTitle = MarqueeLabel(labelWithString: "")
    private var detailsControls: NSStackView!
    private var detailsTrailing: NSStackView!
    private var detailsInfo: NSView!
    private var detailsWidth: NSLayoutConstraint!
    private var blockSongButton: NSButton!
    private var blockArtistButton: NSButton!
    private var scrubClosing = false
    private var scrubCloseWork: DispatchWorkItem?
    private var scrubCloseGeneration = 0
    private var scrubTrackKey = ""
    private let titleLabel = MarqueeLabel(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let progressView = TrackProgressView()
    private let seekSurface = SeekSurface(frame: .zero)
    private let seekTimeBadge = SeekTimeBadge(frame: .zero)
    private var seekWidth: NSLayoutConstraint!
    private var progressAnimationTimer: Timer?
    private var lastScrubFrameAt: Double?
    private var lastCompactFrameAt: Double?
    private var compactTimeText = ""
    private var compactTimePending = false
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
        let controls = NSCustomTouchBarItem(identifier: .init("com.sezerbudak.MediaHub.controls"))
        controls.view = leftSlot

        let escape = NSCustomTouchBarItem(identifier: .init("com.sezerbudak.MediaHub.emptyEscape"))
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
        timelineStack.toolTip = L("touchbar.open_seek_hint")
        NSLayoutConstraint.activate([
            timelineStack.widthAnchor.constraint(equalToConstant: 112),
            timelineStack.heightAnchor.constraint(equalToConstant: 28),
            timeLabel.topAnchor.constraint(equalTo: timelineStack.topAnchor, constant: 1),
            timeLabel.leadingAnchor.constraint(equalTo: timelineStack.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: timelineStack.trailingAnchor),
            timeLabel.heightAnchor.constraint(equalToConstant: 16),
            progressView.leadingAnchor.constraint(equalTo: timelineStack.leadingAnchor, constant: 3),
            progressView.trailingAnchor.constraint(equalTo: timelineStack.trailingAnchor, constant: -3),
            progressView.bottomAnchor.constraint(equalTo: timelineStack.bottomAnchor, constant: -3),
            progressView.heightAnchor.constraint(equalToConstant: 7)
        ])
        progressView.setAccessibilityLabel(L("touchbar.playback_progress"))
        timelineView = timelineStack
        let trailing = NSStackView(views: [timelineStack])
        trailing.spacing = 7
        trailing.alignment = .centerY
        normalTrailing = trailing
        rightSlot = LayoutReportingStack(views: [trailing])
        rightSlot.onLayout = { [weak self] in self?.scheduleSongSizing() }
        rightSlot.spacing = 0
        rightSlot.alignment = .centerY
        rightSlot.detachesHiddenViews = true
        let timelineItem = NSCustomTouchBarItem(identifier: .init("com.sezerbudak.MediaHub.timeline"))
        timelineItem.visibilityPriority = .high
        timelineItem.view = rightSlot
        bar.templateItems = [controls, escape, timelineItem]
        bar.escapeKeyReplacementItemIdentifier = escape.identifier
        bar.defaultItemIdentifiers = [controls.identifier, .flexibleSpace, timelineItem.identifier]
        makeScrubBar()
        makeDetailsBar()
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
        backButton = button("backward.end.fill", L("playback.previous"), #selector(previous))
        playButton = button("play.fill", L("playback.toggle"), #selector(toggle))
        nextButton = button("forward.end.fill", L("playback.next"), #selector(next))
        for (control, forward) in [(backButton!, false), (nextButton!, true)] {
            guard let hold = control as? HoldMediaButton else { continue }
            hold.configureHold()
            hold.onHold = { [weak self] began in
                self?.onAction?(began ? .beginSeeking(forward: forward) : .endSeeking)
            }
        }
        let showDetails = NSClickGestureRecognizer(target: self, action: #selector(toggleDetails))
        showDetails.allowedTouchTypes = .direct
        text.addGestureRecognizer(showDetails)
        favoriteButton = button("star", L("favorite.add"), #selector(toggleFavorite))
        let stack = NSStackView(views: [backButton, playButton, nextButton, text])
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.distribution = .fill
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        return stack
    }

    private func makeScrubBar() {
        seekWidth = seekSurface.widthAnchor.constraint(equalToConstant: 540)
        seekWidth.priority = NSLayoutConstraint.Priority(999)
        seekWidth.isActive = true
        seekSurface.heightAnchor.constraint(equalToConstant: 30).isActive = true
        seekSurface.wantsLayer = true
        seekSurface.onPreview = { [weak self] fraction in
            guard let self, self.scrubOpen, !self.scrubClosing, self.scrubTrackKey == self.state.trackKey else { return }
            self.updateSeekTime(position: fraction * self.state.timeline.duration, emphasized: true)
        }
        seekSurface.onCommit = { [weak self] fraction in
            guard let self, self.scrubOpen, !self.scrubClosing, self.state.timeline.isValid,
                  self.scrubTrackKey == self.state.trackKey else { return }
            self.updateSeekTime(position: fraction * self.state.timeline.duration, emphasized: true)
            self.onAction?(.seek(fraction: fraction, trackKey: self.scrubTrackKey))
        }
        seekSurface.onCancel = { [weak self] in
            self?.refreshProgress()
        }
        seekSurface.isHidden = true
        leftSlot.addArrangedSubview(seekSurface)
        let target = seekTimeBadge
        NSLayoutConstraint.activate([
            target.widthAnchor.constraint(equalToConstant: 112),
            target.heightAnchor.constraint(equalToConstant: 30)
        ])
        let tap = NSClickGestureRecognizer(target: self, action: #selector(toggleScrubber(_:)))
        tap.allowedTouchTypes = .direct
        target.addGestureRecognizer(tap)
        target.toolTip = L("touchbar.return_hint")
        expandedTime = target
        target.isHidden = true
        rightSlot.addArrangedSubview(target)
    }

    private func makeDetailsBar() {
        detailsTitle.lineBreakMode = .byTruncatingTail
        detailsTitle.maximumNumberOfLines = 1
        detailsTitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let info = NSStackView(views: [detailsTitle])
        info.alignment = .centerY
        info.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        info.wantsLayer = true
        info.layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        info.layer?.cornerRadius = 7
        info.heightAnchor.constraint(equalToConstant: 28).isActive = true
        detailsTitle.translatesAutoresizingMaskIntoConstraints = false
        detailsTitle.widthAnchor.constraint(equalTo: info.widthAnchor, constant: -20).isActive = true
        detailsWidth = info.widthAnchor.constraint(equalToConstant: 280)
        detailsWidth.priority = NSLayoutConstraint.Priority(999)
        detailsWidth.isActive = true
        detailsInfo = info
        let close = NSClickGestureRecognizer(target: self, action: #selector(toggleDetails))
        close.allowedTouchTypes = .direct
        info.addGestureRecognizer(close)
        detailsControls = NSStackView(views: [favoriteButton, info])
        detailsControls.spacing = 7
        detailsControls.alignment = .centerY
        detailsControls.detachesHiddenViews = true
        detailsControls.isHidden = true
        leftSlot.addArrangedSubview(detailsControls)
        blockSongButton = blacklistButton(L("blacklist.block_song"), symbol: "music.note", width: 106, action: #selector(toggleSongBlacklist))
        blockArtistButton = blacklistButton(L("blacklist.block_artist"), symbol: "person.fill", width: 116, action: #selector(toggleArtistBlacklist))
        detailsTrailing = NSStackView(views: [blockSongButton, blockArtistButton])
        detailsTrailing.spacing = 7
        detailsTrailing.alignment = .centerY
        detailsTrailing.isHidden = true
        rightSlot.addArrangedSubview(detailsTrailing)
    }

    private func blacklistButton(_ title: String, symbol: String, width: CGFloat, action: Selector) -> NSButton {
        let button = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!,
                              target: self, action: action)
        button.bezelStyle = .rounded
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.font = .systemFont(ofSize: 10.5, weight: .medium)
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        return button
    }

    func render(_ newState: MediaState) {
        let animateTitleChange = state.hasMedia && newState.hasMedia && newState.trackKey != state.trackKey
        if newState.trackKey != state.trackKey { lastCompactFrameAt = nil }
        if newState.trackKey != state.trackKey || !newState.timeline.isValid { closeScrubber() }
        if newState.trackKey != state.trackKey || !newState.hasMedia { closeDetails() }
        state = newState
        timelineView.toolTip = L("touchbar.open_seek_hint")
        progressView.setAccessibilityLabel(L("touchbar.playback_progress"))
        [backButton, playButton, nextButton].forEach { $0?.isEnabled = state.hasMedia }
        backButton.toolTip = state.isPodcast ? L("playback.back_15_seconds") : L("playback.previous")
        playButton.toolTip = L("playback.toggle")
        nextButton.toolTip = state.isPodcast ? L("playback.forward_15_seconds") : L("playback.next")
        expandedTime.setAccessibilityLabel(L("touchbar.close_seek"))
        expandedTime.toolTip = L("touchbar.return_hint")
        seekSurface.setAccessibilityLabel(L("touchbar.playback_position"))
        playButton.image = NSImage(systemSymbolName: state.playing ? "pause.fill" : "play.fill", accessibilityDescription: L("playback.toggle"))
        backButton.image = NSImage(systemSymbolName: state.isPodcast ? "gobackward.15" : "backward.end.fill", accessibilityDescription: state.isPodcast ? L("playback.back_15_seconds") : L("playback.previous"))
        nextButton.image = NSImage(systemSymbolName: state.isPodcast ? "goforward.15" : "forward.end.fill", accessibilityDescription: state.isPodcast ? L("playback.forward_15_seconds") : L("playback.next"))
        favoriteButton.isHidden = !state.hasMedia || !state.isMusic
        favoriteButton.isEnabled = state.hasMedia && state.isMusic && !state.favoritePending
        let favoriteAction = state.favorite ? L("favorite.remove") : L("favorite.add")
        favoriteButton.image = NSImage(systemSymbolName: state.favorite ? "star.fill" : "star", accessibilityDescription: favoriteAction)
        favoriteButton.toolTip = state.favoritePending ? "\(favoriteAction) · \(L("favorite.pending"))" : favoriteAction
        favoriteButton.setAccessibilityLabel(favoriteAction)
        favoriteButton.setAccessibilityValue(state.favorite ? L("favorite.active") : L("favorite.inactive"))
        blockSongButton.isEnabled = state.canEditBlacklist && state.songBlacklistEntry != nil
        blockArtistButton.isEnabled = state.canEditBlacklist && state.primaryArtistBlacklistEntry != nil
        blockSongButton.title = state.songBlacklisted ? L("blacklist.song_blocked") : L("blacklist.block_song")
        blockArtistButton.title = state.primaryArtistBlacklisted ? L("blacklist.artist_blocked") : L("blacklist.block_artist")
        blockSongButton.contentTintColor = state.songBlacklisted ? .systemPink : .white
        blockArtistButton.contentTintColor = state.primaryArtistBlacklisted ? .systemPink : .white
        blockSongButton.toolTip = state.songBlacklisted ? L("blacklist.remove_song_hint") : L("blacklist.add_song_hint")
        let artistName = state.artistNames.first ?? state.artistText
        blockArtistButton.toolTip = "\(state.primaryArtistBlacklisted ? L("blacklist.remove") : L("blacklist.add")): \(artistName)"
        renderTitle(animateChange: animateTitleChange)
        detailsTitle.setText(titleLabel.attributedStringValue, animateChange: false)
        refreshProgress()
        scheduleSongSizing()
    }

    private func renderTitle(animateChange: Bool) {
        guard state.hasMedia else {
            titleLabel.cancelTransition()
            titleLabel.attributedStringValue = NSAttributedString(string: "♫  \(L("playback.waiting"))", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 0.55, alpha: 1)])
            titleLabel.toolTip = L("playback.waiting")
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
        let trackDescription = state.artist.isEmpty ? state.title : "\(state.title) — \(state.artist)"
        titleLabel.toolTip = "\(trackDescription) · \(L("touchbar.open_actions"))"
        detailsTitle.toolTip = "\(trackDescription) · \(L("touchbar.return"))"
    }

    func refreshProgress() {
        timelineView.isHidden = !state.timeline.isValid
        guard state.timeline.isValid else { updateProgressAnimation(); return }
        refreshCompactProgress()
        if scrubOpen && !seekSurface.isDragging {
            refreshSeekProgress()
        }
        updateProgressAnimation()
    }

    private func refreshCompactProgress() {
        guard state.timeline.isValid else { return }
        let now = CACurrentMediaTime()
        let position = state.timeline.position(at: Date().timeIntervalSince1970)
        let target = position / state.timeline.duration
        if presented, !scrubOpen, state.timeline.isAdvancing,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let lastCompactFrameAt, now - lastCompactFrameAt < 0.2 {
            let weight = 1 - exp(-max(0, now - lastCompactFrameAt) / 0.06)
            progressView.fraction += (target - progressView.fraction) * weight
        } else {
            progressView.fraction = target
        }
        lastCompactFrameAt = now
        progressView.isAdvancing = state.timeline.isAdvancing
        let text = timeText(position)
        if text != compactTimeText || state.seekPending != compactTimePending {
            compactTimeText = text
            compactTimePending = state.seekPending
            let value = NSMutableAttributedString(string: PlaybackTimeline.format(position), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: state.seekPending ? NSColor.systemPink : NSColor(white: 0.62, alpha: 1)
            ])
            value.append(NSAttributedString(string: " / ", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(white: 0.32, alpha: 1)
            ]))
            value.append(NSAttributedString(string: PlaybackTimeline.format(state.timeline.duration), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(white: 0.62, alpha: 1)
            ]))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byClipping
            value.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: value.length))
            timeLabel.attributedStringValue = value
            progressView.setAccessibilityValue(text)
        }
    }

    private func refreshSeekProgress() {
        guard scrubOpen, !scrubClosing, state.timeline.isValid, !seekSurface.isDragging else { return }
        let now = CACurrentMediaTime()
        let position = state.timeline.position(at: Date().timeIntervalSince1970)
        let target = position / state.timeline.duration
        let canSmooth = presented && state.timeline.isAdvancing
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if canSmooth, let lastScrubFrameAt, now - lastScrubFrameAt < 0.2 {
            // A short, time-based filter absorbs small metadata corrections.
            // Finger gestures and released seek targets always bypass it.
            let weight = 1 - exp(-max(0, now - lastScrubFrameAt) / 0.06)
            seekSurface.fraction += (target - seekSurface.fraction) * weight
        } else {
            seekSurface.fraction = target
        }
        lastScrubFrameAt = now
        updateSeekTime(position: position, emphasized: state.seekPending)
    }

    private func updateProgressAnimation() {
        let shouldAnimate = presented && !scrubClosing && !detailsOpen
            && state.timeline.isAdvancing
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else {
            progressAnimationTimer?.invalidate()
            progressAnimationTimer = nil
            lastScrubFrameAt = nil
            lastCompactFrameAt = nil
            return
        }
        guard progressAnimationTimer == nil else { return }
        // Share one frame timer between the compact and expanded surfaces.
        // Hidden surfaces and the media polling rate are left untouched.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.scrubOpen { self.refreshSeekProgress() }
            else { self.refreshCompactProgress() }
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        progressAnimationTimer = timer
    }

    private func updateSeekTime(position: Double, emphasized: Bool) {
        seekTimeBadge.update(position: position, duration: state.timeline.duration, emphasized: emphasized)
        seekSurface.setAccessibilityValue(timeText(position))
    }

    private func timeText(_ position: Double) -> String {
        "\(PlaybackTimeline.format(position)) / \(PlaybackTimeline.format(state.timeline.duration))"
    }

    @objc private func toggleScrubber(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended, !scrubClosing else { return }
        if scrubOpen { closeScrubber(animated: true); return }
        guard state.timeline.isValid else { return }
        closeDetails()
        onAction?(.endSeeking)
        scrubTrackKey = state.trackKey
        scrubOpen = true
        refreshProgress()
        updateModeViews(animateOpening: true)
    }

    private func closeScrubber(animated: Bool = false) {
        guard scrubOpen else { return }
        scrubCloseWork?.cancel()
        scrubCloseGeneration += 1
        if animated, presented, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            scrubClosing = true
            updateProgressAnimation()
            seekSurface.cancelInteraction()
            animateScrubViews([(seekSurface, 16), (expandedTime, 6)], appearing: false, duration: 0.16)
            let generation = scrubCloseGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.scrubClosing, self.scrubCloseGeneration == generation else { return }
                self.closeScrubber()
                self.animateScrubViews([(self.normalControls, -8), (self.normalTrailing, -3)], appearing: true, duration: 0.08)
            }
            scrubCloseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
            return
        }
        scrubCloseWork = nil
        scrubClosing = false
        scrubOpen = false
        updateProgressAnimation()
        seekSurface.cancelInteraction()
        updateModeViews()
    }

    private func updateModeViews(animateOpening: Bool = false) {
        [seekSurface, expandedTime, normalControls, normalTrailing, detailsControls, detailsTrailing].forEach { $0?.layer?.removeAnimation(forKey: "scrub.reveal") }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            normalControls.isHidden = scrubOpen || detailsOpen
            normalTrailing.isHidden = scrubOpen || detailsOpen
            seekSurface.isHidden = !scrubOpen
            expandedTime.isHidden = !scrubOpen
            detailsControls.isHidden = !detailsOpen
            detailsTrailing.isHidden = !detailsOpen
            leftSlot.layoutSubtreeIfNeeded()
            rightSlot.layoutSubtreeIfNeeded()
            CATransaction.commit()
        }
        titleLabel.animationsEnabled = presented && !scrubOpen && !detailsOpen
        detailsTitle.animationsEnabled = presented && detailsOpen
        updateProgressAnimation()
        resizeContentToAvailableWidth()
        if animateOpening, presented, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let views: [(NSView, Double)] = detailsOpen
                ? [(detailsControls, 16), (detailsTrailing, 6)]
                : [(seekSurface, 16), (expandedTime, 6)]
            animateScrubViews(views, appearing: true, duration: 0.24)
        }
        scheduleSongSizing()
    }

    private func animateScrubViews(_ views: [(NSView, Double)], appearing: Bool, duration: Double) {
        guard presented, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        for (view, distance) in views {
            view.wantsLayer = true
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = appearing ? 0 : (view.layer?.presentation()?.opacity ?? 1)
            fade.toValue = appearing ? 1 : 0
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = appearing ? distance : 0
            slide.toValue = appearing ? 0 : distance
            let animation = CAAnimationGroup()
            animation.animations = [fade, slide]
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: appearing ? .easeOut : .easeIn)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = appearing
            view.layer?.add(animation, forKey: "scrub.reveal")
        }
    }

    func setPresented(_ visible: Bool) {
        presented = visible
        if !visible { closeScrubber(); closeDetails() }
        updateProgressAnimation()
        titleLabel.animationsEnabled = visible && !scrubOpen && !detailsOpen
        detailsTitle.animationsEnabled = visible && detailsOpen
        scheduleSongSizing()
    }

    private func scheduleSongSizing() {
        guard presented else { return }
        songSizingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.resizeContentToAvailableWidth() }
        songSizingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func resizeContentToAvailableWidth() {
        guard presented, let window = leftSlot.window, window === rightSlot.window else { return }
        let left = leftSlot.convert(leftSlot.bounds, to: nil)
        let availableWidth = window.contentView?.bounds.width ?? window.frame.width
        let constraint: NSLayoutConstraint
        let width: CGFloat
        if scrubOpen {
            // Give the ruler the space formerly reserved for transport buttons,
            // song text and favorites, keeping the time badge and system controls.
            constraint = seekWidth
            width = min(560, max(160, availableWidth - left.minX - rightSlot.fittingSize.width - 24))
        } else if detailsOpen {
            constraint = detailsWidth
            let favoriteWidth: CGFloat = favoriteButton.isHidden ? 0 : 55
            width = min(340, max(100, availableWidth - left.minX - favoriteWidth - rightSlot.fittingSize.width - 24))
        } else {
            constraint = songWidth
            let navigationWidth = normalControls.bounds.width - songInfoView.bounds.width
            let trailingWidth = max(112, rightSlot.fittingSize.width)
            width = min(375, max(100, availableWidth - left.minX - navigationWidth - trailingWidth - 24))
        }
        guard width.isFinite, abs(constraint.constant - width) > 0.5 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            constraint.constant = width
            songInfoView.invalidateIntrinsicContentSize()
            normalControls.invalidateIntrinsicContentSize()
            detailsInfo.invalidateIntrinsicContentSize()
            detailsControls.invalidateIntrinsicContentSize()
            leftSlot.invalidateIntrinsicContentSize()
            leftSlot.layoutSubtreeIfNeeded()
        }
    }

    func stop() {
        songSizingWork?.cancel()
        closeScrubber()
        closeDetails()
        setPresented(false)
        onAction = nil
    }

    @objc private func toggle() { onAction?(.togglePlayback) }
    @objc private func previous() { onAction?(.previous) }
    @objc private func next() { onAction?(.next) }
    @objc private func toggleDetails() {
        guard state.hasMedia, !scrubClosing else { return }
        if detailsOpen { closeDetails(animated: true); return }
        closeScrubber()
        onAction?(.endSeeking)
        detailsOpen = true
        updateModeViews(animateOpening: true)
    }

    private func closeDetails(animated: Bool = false) {
        guard detailsOpen else { return }
        detailsOpen = false
        updateModeViews()
        if animated {
            animateScrubViews([(normalControls, -8), (normalTrailing, -3)], appearing: true, duration: 0.24)
        }
    }

    @objc private func toggleSongBlacklist() {
        guard detailsOpen, let entry = state.songBlacklistEntry else { return }
        onAction?(.toggleBlacklist(entry, trackKey: state.trackKey))
    }

    @objc private func toggleArtistBlacklist() {
        guard detailsOpen, let entry = state.primaryArtistBlacklistEntry else { return }
        onAction?(.toggleBlacklist(entry, trackKey: state.trackKey))
    }
    @objc private func toggleFavorite() {
        guard detailsOpen else { return }
        onAction?(.toggleFavorite)
    }
}

private final class TrackProgressView: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var isAdvancing = false { didSet { if isAdvancing != oldValue { needsDisplay = true } } }
    override var intrinsicContentSize: NSSize { NSSize(width: 80, height: 28) }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0.5, y: bounds.midY - 3, width: max(1, bounds.width - 1), height: 6)
        let shape = NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3)
        NSColor(white: 0.16, alpha: 1).setFill()
        shape.fill()
        let progress = fraction.isFinite ? min(1, max(0, fraction)) : 0
        guard progress > 0 else { return }
        let played = NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: track.height)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor.systemPink.withAlphaComponent(isAdvancing ? 1 : 0.65).setFill()
        NSBezierPath(roundedRect: played, xRadius: 3, yRadius: 3).fill()
        NSGraphicsContext.restoreGraphicsState()
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

/// The expanded mode keeps the compact, single-line time format without a backdrop.
private final class SeekTimeBadge: NSView {
    private let label = NSTextField(labelWithString: "")
    private let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = timeFont
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.heightAnchor.constraint(equalToConstant: 18)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L("touchbar.close_seek"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(position: Double, duration: Double, emphasized: Bool) {
        let font = timeFont
        let normalColor = NSColor(white: 0.62, alpha: 1)
        let text = NSMutableAttributedString(string: PlaybackTimeline.format(position), attributes: [
            .font: font, .foregroundColor: emphasized ? NSColor.systemPink : normalColor
        ])
        text.append(NSAttributedString(string: " / \(PlaybackTimeline.format(duration))", attributes: [
            .font: font, .foregroundColor: normalColor
        ]))
        // The playhead moves every frame; time text changes only each second
        // or when the drag/confirmation highlight changes.
        if !label.attributedStringValue.isEqual(to: text) {
            label.attributedStringValue = text
            setAccessibilityValue(text.string)
        }
    }
}

/// A large direct-touch target for the expanded seek screen. Dragging previews;
/// only releasing a successful gesture sends a seek command.
final class SeekSurface: NSView, NSGestureRecognizerDelegate {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var onPreview: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var isDragging = false { didSet { needsDisplay = true } }
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
        setAccessibilityLabel(L("touchbar.playback_position"))
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
            // Touch-up may no longer report the last finger location. Commit
            // the final preview instead of briefly moving to a spurious value.
            onCommit?(fraction)
        case .cancelled, .failed:
            let wasDragging = isDragging
            isDragging = false
            if wasDragging { onCancel?() }
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
        let track = NSRect(x: 8, y: bounds.midY - 10, width: max(1, bounds.width - 16), height: 20)
        let shape = NSBezierPath(roundedRect: track, xRadius: 6, yRadius: 6)
        let x = track.minX + track.width * (fraction.isFinite ? min(1, max(0, fraction)) : 0)

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(starting: NSColor(white: 0.10, alpha: 1), ending: NSColor(white: 0.045, alpha: 1))?
            .draw(in: track, angle: 90)
        if x > track.minX {
            let played = NSRect(x: track.minX, y: track.minY, width: x - track.minX, height: track.height)
            NSGradient(starting: NSColor.systemPink.withAlphaComponent(0.36),
                       ending: NSColor.systemPink.withAlphaComponent(isDragging ? 0.88 : 0.68))?
                .draw(in: played, angle: 0)
        }

        // These are evenly spaced ruler marks, not a simulated audio waveform.
        let tickCount = max(1, Int((track.width - 12) / 8))
        for index in 0...tickCount {
            let tickX = track.minX + 6 + CGFloat(index) * (track.width - 12) / CGFloat(tickCount)
            let height: CGFloat = index.isMultiple(of: 5) ? 10 : 5
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: tickX, y: track.midY - height / 2))
            tick.line(to: NSPoint(x: tickX, y: track.midY + height / 2))
            tick.lineWidth = 1
            (tickX <= x ? NSColor.white.withAlphaComponent(0.54) : NSColor.white.withAlphaComponent(0.19)).setStroke()
            tick.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.09).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()

        // A bright playhead replaces the round slider knob. Its hit area is
        // still the full 30pt surface, so precision does not cost touch comfort.
        let playhead = NSBezierPath(roundedRect: NSRect(x: x - 2, y: bounds.midY - 12, width: 4, height: 24), xRadius: 2, yRadius: 2)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.systemPink.withAlphaComponent(isDragging ? 0.6 : 0.25)
        glow.shadowBlurRadius = isDragging ? 7 : 4
        glow.shadowOffset = .zero
        glow.set()
        NSColor.white.setFill()
        playhead.fill()
        NSGraphicsContext.restoreGraphicsState()
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
