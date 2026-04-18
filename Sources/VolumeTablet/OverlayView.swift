import AppKit

enum SurfaceRoute: String, CaseIterable {
    case volume
    case low
    case mid
    case high

    var eyebrow: String {
        switch self {
        case .volume: return "VOLUME"
        case .low: return "LOW BAND"
        case .mid: return "MID BAND"
        case .high: return "HIGH BAND"
        }
    }

    var title: String {
        rawValue
    }

    var navigationTitle: String {
        switch self {
        case .volume: return "Volume"
        case .low: return "Low"
        case .mid: return "Mid"
        case .high: return "High"
        }
    }

    var metaText: String {
        switch self {
        case .volume: return "Path: Master"
        case .low: return "Band: Low"
        case .mid: return "Band: Mid"
        case .high: return "Band: High"
        }
    }

    var rangeText: String {
        switch self {
        case .volume:
            return "Absolute Y position controls MacBook output volume below the top safe band."
        case .low:
            return "Absolute Y position controls the low EQ band below the top safe band."
        case .mid:
            return "Absolute Y position controls the mid EQ band below the top safe band."
        case .high:
            return "Absolute Y position controls the high EQ band below the top safe band."
        }
    }

    var dragText: String {
        switch self {
        case .volume:
            return "Drag anywhere below the top safe band to raise output volume. Drag down to lower it."
        case .low:
            return "Drag anywhere below the top safe band to boost or cut the low band."
        case .mid:
            return "Drag anywhere below the top safe band to boost or cut the mid band."
        case .high:
            return "Drag anywhere below the top safe band to boost or cut the high band."
        }
    }

    var hoverText: String {
        switch self {
        case .volume:
            return "Hover anywhere below the top safe band to raise or lower output volume."
        case .low:
            return "Hover anywhere below the top safe band to boost or cut the low band."
        case .mid:
            return "Hover anywhere below the top safe band to boost or cut the mid band."
        case .high:
            return "Hover anywhere below the top safe band to boost or cut the high band."
        }
    }

    var accent: NSColor {
        switch self {
        case .volume:
            return NSColor(calibratedRed: 0.44, green: 0.94, blue: 0.76, alpha: 1)
        case .low:
            return NSColor(calibratedRed: 1.00, green: 0.61, blue: 0.42, alpha: 1)
        case .mid:
            return NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.43, alpha: 1)
        case .high:
            return NSColor(calibratedRed: 0.48, green: 0.73, blue: 1.00, alpha: 1)
        }
    }

    var accentSoft: NSColor {
        accent.withAlphaComponent(0.24)
    }

    var accentGlow: NSColor {
        accent.withAlphaComponent(0.44)
    }

    var resetValue: Int {
        50
    }

    var bandKey: String? {
        switch self {
        case .volume: return nil
        case .low: return "low"
        case .mid: return "mid"
        case .high: return "high"
        }
    }

    var routeKey: String {
        switch self {
        case .volume: return "1"
        case .low: return "2"
        case .mid: return "3"
        case .high: return "4"
        }
    }
}

enum SurfaceInteraction {
    case idle
    case dragging
    case hovering
}

struct SurfaceSnapshot {
    var route: SurfaceRoute = .volume
    var value: Int = 50
    var hoverMode = false
    var interaction: SurfaceInteraction = .idle
    var statusText = "Loading"
    var backendName = "native-eq"
    var backendDetail = ""
    var connected = false
}

extension Notification.Name {
    static let controlSurfaceStateDidChange = Notification.Name("ControlSurfaceStateDidChange")
}

final class ControlSurfaceState {
    private(set) var snapshot = SurfaceSnapshot()

    func update(_ change: (inout SurfaceSnapshot) -> Void) {
        change(&snapshot)
        NotificationCenter.default.post(name: .controlSurfaceStateDidChange, object: self)
    }
}

final class ControlSurfaceController {
    private let bridge = EqBridgeClient()
    let state: ControlSurfaceState

    private var routeVersion = 0

    init(state: ControlSurfaceState) {
        self.state = state
    }

    func start() {
        refreshCurrentRoute()
    }

    func stop() {
        bridge.stop()
    }

    func navigate(to route: SurfaceRoute) {
        routeVersion += 1
        let version = routeVersion
        state.update { snapshot in
            snapshot.route = route
            snapshot.interaction = .idle
            snapshot.statusText = "Loading"
        }

        let response = bridge.status(for: route)
        guard version == routeVersion, state.snapshot.route == route else { return }
        apply(response: response, updateStatus: true)
    }

    func refreshCurrentRoute() {
        let route = state.snapshot.route
        let version = routeVersion
        let response = bridge.status(for: route)
        guard version == routeVersion, state.snapshot.route == route else { return }
        apply(response: response, updateStatus: true)
    }

    func toggleMode() {
        state.update { snapshot in
            snapshot.hoverMode.toggle()
            snapshot.interaction = .idle
            snapshot.statusText = snapshot.hoverMode ? "Hover ready" : "Drag ready"
        }
    }

    func centerCurrentRoute() {
        setLiveValue(state.snapshot.route.resetValue, interaction: .idle)
        state.update { snapshot in
            snapshot.statusText = "Centered"
        }
    }

    func setLiveValue(_ value: Int, interaction: SurfaceInteraction) {
        let clamped = max(0, min(100, value))
        let route = state.snapshot.route
        let version = routeVersion

        state.update { snapshot in
            snapshot.value = clamped
            snapshot.interaction = interaction
            snapshot.statusText = "Live"
        }

        let response = bridge.setValue(clamped, for: route)
        guard version == routeVersion, state.snapshot.route == route else { return }
        apply(response: response, updateStatus: false)
    }

    func endDrag() {
        state.update { snapshot in
            snapshot.interaction = .idle
            snapshot.statusText = snapshot.hoverMode ? "Hover ready" : "Drag ready"
        }
    }

    func setHoverReady() {
        state.update { snapshot in
            if snapshot.hoverMode {
                snapshot.interaction = .idle
                snapshot.statusText = "Hover ready"
            }
        }
    }

    private func apply(response: EqBridgeResponse, updateStatus: Bool) {
        state.update { snapshot in
            if let value = response.value {
                snapshot.value = value
            }
            snapshot.connected = response.connected
            snapshot.backendName = response.backend
            snapshot.backendDetail = response.detail
            if updateStatus {
                snapshot.statusText = snapshot.hoverMode ? "Hover ready" : "Drag ready"
            }
        }
    }
}

final class ControlSurfaceView: NSView {
    private let screen: NSScreen
    private let state: ControlSurfaceState
    private let controller: ControlSurfaceController
    private let onRequestFullscreen: () -> Void

    private let actionsStack = NSStackView()
    private let navStack = NSStackView()
    private let brandMarkView = NSImageView()
    private let brandNameLabel = NSTextField(labelWithString: "StylusDeck")
    private let modeButton = PillButton()
    private let fullscreenButton = PillButton()
    private let centerButton = PillButton()
    private let routeButtons = SurfaceRoute.allCases.reduce(into: [SurfaceRoute: PillButton]()) { partialResult, route in
        partialResult[route] = PillButton()
    }

    private let eyebrowLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subcopyLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let rangeNoteLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")

    private var trackingAreaRef: NSTrackingArea?
    private var snapshot = SurfaceSnapshot()

    override var acceptsFirstResponder: Bool { true }

    init(
        frame frameRect: NSRect,
        screen: NSScreen,
        state: ControlSurfaceState,
        controller: ControlSurfaceController,
        onRequestFullscreen: @escaping () -> Void
    ) {
        self.screen = screen
        self.state = state
        self.controller = controller
        self.onRequestFullscreen = onRequestFullscreen
        super.init(frame: frameRect)
        wantsLayer = true

        setupButtons()
        setupLabels()
        setupBranding()
        installSubviews()
        refreshFromState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .controlSurfaceStateDidChange,
            object: state
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func layout() {
        super.layout()
        layoutTopBars()
        layoutHero()
        layoutFooter()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let route = snapshot.route

        drawBackground(in: context, accent: route.accent, accentSoft: route.accentSoft)
        drawSafeBand(in: context)
        drawLiveLine(in: context, accent: route.accent, glow: route.accentGlow)
        drawRail(in: context, accent: route.accent, glow: route.accentGlow)
    }

    override func mouseDown(with event: NSEvent) {
        guard !snapshot.hoverMode else { return }
        updateFromPointer(event, interaction: .dragging)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !snapshot.hoverMode else { return }
        updateFromPointer(event, interaction: .dragging)
    }

    override func mouseUp(with event: NSEvent) {
        controller.endDrag()
    }

    override func mouseMoved(with event: NSEvent) {
        guard snapshot.hoverMode else { return }
        updateFromPointer(event, interaction: .hovering)
    }

    override func mouseExited(with event: NSEvent) {
        controller.setHoverReady()
    }

    override func tabletPoint(with event: NSEvent) {
        if snapshot.hoverMode || event.pressure > 0 {
            updateFromPointer(event, interaction: snapshot.hoverMode ? .hovering : .dragging)
        }
    }

    override func pressureChange(with event: NSEvent) {
        if event.pressure > 0 {
            updateFromPointer(event, interaction: snapshot.hoverMode ? .hovering : .dragging)
        } else if snapshot.hoverMode {
            controller.setHoverReady()
        } else {
            controller.endDrag()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        NSApp.terminate(nil)
    }

    @objc
    private func handleStateChange() {
        refreshFromState()
    }

    @objc
    private func handleModeButton() {
        controller.toggleMode()
        window?.makeFirstResponder(self)
    }

    @objc
    private func handleFullscreenButton() {
        onRequestFullscreen()
        controller.state.update { snapshot in
            snapshot.statusText = "Fullscreen"
        }
        window?.makeFirstResponder(self)
    }

    @objc
    private func handleCenterButton() {
        controller.centerCurrentRoute()
        window?.makeFirstResponder(self)
    }

    @objc
    private func handleRouteButton(_ sender: PillButton) {
        guard let route = sender.route else { return }
        controller.navigate(to: route)
        window?.makeFirstResponder(self)
    }

    private func setupButtons() {
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 12
        actionsStack.alignment = .centerY

        navStack.orientation = .horizontal
        navStack.spacing = 10
        navStack.alignment = .centerY

        modeButton.target = self
        modeButton.action = #selector(handleModeButton)

        fullscreenButton.target = self
        fullscreenButton.action = #selector(handleFullscreenButton)

        centerButton.target = self
        centerButton.action = #selector(handleCenterButton)

        modeButton.title = "Mode: Drag"
        fullscreenButton.title = "Fullscreen"
        centerButton.title = "Center"

        [modeButton, fullscreenButton, centerButton].forEach {
            actionsStack.addArrangedSubview($0)
        }

        for route in SurfaceRoute.allCases {
            if let button = routeButtons[route] {
                button.route = route
                button.title = route.navigationTitle
                button.target = self
                button.action = #selector(handleRouteButton(_:))
                navStack.addArrangedSubview(button)
            }
        }
    }

    private func setupLabels() {
        [brandNameLabel, eyebrowLabel, valueLabel, subcopyLabel, metaLabel, rangeNoteLabel, statusLabel].forEach { label in
            label.isBordered = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            addSubview(label)
        }

        brandNameLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        eyebrowLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        valueLabel.textColor = .white
        subcopyLabel.textColor = NSColor.white.withAlphaComponent(0.82)
        metaLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        rangeNoteLabel.textColor = NSColor.white.withAlphaComponent(0.52)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.68)

        eyebrowLabel.alignment = .left
        valueLabel.alignment = .left
        subcopyLabel.alignment = .left
        metaLabel.alignment = .left
        rangeNoteLabel.alignment = .left
        statusLabel.alignment = .right
    }

    private func setupBranding() {
        brandMarkView.image = BrandAssets.markImage()
        brandMarkView.imageScaling = .scaleProportionallyUpOrDown
        brandMarkView.alphaValue = 0.96
        addSubview(brandMarkView)
    }

    private func installSubviews() {
        addSubview(actionsStack)
        addSubview(navStack)
    }

    private func refreshFromState() {
        snapshot = state.snapshot
        updateButtonStyles()
        updateLabels()
        needsLayout = true
        needsDisplay = true
    }

    private func updateButtonStyles() {
        let accent = snapshot.route.accent
        modeButton.title = "Mode: \(snapshot.hoverMode ? "Hover" : "Drag")"

        modeButton.applyStyle(background: NSColor.white.withAlphaComponent(0.10), text: .white)
        fullscreenButton.applyStyle(background: accent, text: NSColor(calibratedWhite: 0.06, alpha: 1))
        centerButton.applyStyle(background: NSColor.white.withAlphaComponent(0.10), text: .white)

        for route in SurfaceRoute.allCases {
            guard let button = routeButtons[route] else { continue }
            if route == snapshot.route {
                button.applyStyle(background: accent, text: NSColor(calibratedWhite: 0.06, alpha: 1))
            } else {
                button.applyStyle(background: NSColor.white.withAlphaComponent(0.10), text: .white)
            }
        }
    }

    private func updateLabels() {
        let route = snapshot.route

        eyebrowLabel.stringValue = route.eyebrow
        valueLabel.stringValue = "\(snapshot.value)%"
        subcopyLabel.stringValue = snapshot.hoverMode ? route.hoverText : route.dragText
        metaLabel.stringValue = metaString()
        rangeNoteLabel.stringValue = ""
        statusLabel.stringValue = snapshot.statusText
    }

    private func metaString() -> String {
        let backend = snapshot.connected ? snapshot.backendName.uppercased() : "\(snapshot.backendName.uppercased()) · NOT CONNECTED"
        if snapshot.backendDetail.isEmpty {
            return "\(snapshot.route.metaText) · \(backend)"
        }
        return "\(snapshot.route.metaText) · \(backend) · \(snapshot.backendDetail)"
    }

    private func layoutTopBars() {
        let paddingX: CGFloat = 34
        let paddingY: CGFloat = 28
        let topBandCenterY: CGFloat

        actionsStack.setFrameSize(actionsStack.fittingSize)
        navStack.setFrameSize(navStack.fittingSize)
        metaLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)

        actionsStack.frame.origin = NSPoint(
            x: paddingX,
            y: bounds.height - paddingY - actionsStack.frame.height
        )

        navStack.frame.origin = NSPoint(
            x: bounds.width - paddingX - navStack.frame.width,
            y: bounds.height - paddingY - navStack.frame.height
        )

        topBandCenterY = actionsStack.frame.midY

        let gapLeft = actionsStack.frame.maxX + 24
        let gapRight = navStack.frame.minX - 24
        let metaWidth = max(0, gapRight - gapLeft)
        if metaWidth > 0 {
            metaLabel.alignment = .center
            metaLabel.frame = NSRect(
                x: gapLeft,
                y: topBandCenterY - 11,
                width: metaWidth,
                height: 22
            )
        } else {
            metaLabel.frame = .zero
        }
    }

    private func layoutHero() {
        let paddingX: CGFloat = 34
        let heroOriginX = paddingX
        let heroTop = bounds.height * 0.56

        let brandMarkSize = min(max(bounds.width * 0.05, 52), 72)
        eyebrowLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        brandNameLabel.font = NSFont.systemFont(ofSize: min(bounds.width * 0.024, 28), weight: .semibold)
        valueLabel.font = NSFont.systemFont(ofSize: min(bounds.width * 0.18, 196), weight: .black)
        subcopyLabel.font = NSFont.systemFont(ofSize: min(bounds.width * 0.024, 24), weight: .medium)

        brandMarkView.frame = NSRect(
            x: heroOriginX,
            y: bounds.height - controlTop - brandMarkSize - 24,
            width: brandMarkSize,
            height: brandMarkSize
        )

        let brandNameSize = singleLineSize(
            for: brandNameLabel.stringValue,
            font: brandNameLabel.font ?? .systemFont(ofSize: 24)
        )
        brandNameLabel.frame = NSRect(
            x: brandMarkView.frame.maxX + 14,
            y: brandMarkView.frame.midY - brandNameSize.height / 2 + 2,
            width: brandNameSize.width + 6,
            height: brandNameSize.height + 4
        )

        let eyebrowY = brandMarkView.frame.minY - 22
        eyebrowLabel.frame = NSRect(
            x: heroOriginX,
            y: eyebrowY,
            width: 220,
            height: 18
        )

        let valueSize = singleLineSize(for: valueLabel.stringValue, font: valueLabel.font ?? .systemFont(ofSize: 160))
        let valueY = min(heroTop + 18, eyebrowLabel.frame.minY - valueSize.height - 14)
        valueLabel.frame = NSRect(x: heroOriginX, y: valueY, width: valueSize.width + 8, height: valueSize.height + 8)
    }

    private func layoutFooter() {
        let paddingX: CGFloat = 34
        let paddingY: CGFloat = 28
        let footerHeight: CGFloat = 22
        let instructionWidth = min(bounds.width * 0.42, 560)

        rangeNoteLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        subcopyLabel.alignment = .left

        let footerY = paddingY - 2
        let subcopyHeight = multilineHeight(
            for: subcopyLabel.stringValue,
            font: subcopyLabel.font ?? .systemFont(ofSize: 22),
            width: instructionWidth
        )
        subcopyLabel.frame = NSRect(
            x: paddingX + 4,
            y: footerY + footerHeight + 10,
            width: instructionWidth,
            height: subcopyHeight
        )
        rangeNoteLabel.frame = .zero
        statusLabel.frame = NSRect(x: bounds.width - paddingX - 160, y: footerY, width: 160, height: footerHeight)
    }

    private func drawBackground(in context: CGContext, accent: NSColor, accentSoft: NSColor) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let topColor = NSColor(calibratedRed: 0.03, green: 0.06, blue: 0.09, alpha: 1).cgColor
        let bottomColor = NSColor(calibratedRed: 0.01, green: 0.01, blue: 0.02, alpha: 1).cgColor

        if let linearGradient = CGGradient(colorsSpace: colorSpace, colors: [topColor, bottomColor] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(
                linearGradient,
                start: CGPoint(x: bounds.minX, y: bounds.maxY),
                end: CGPoint(x: bounds.maxX, y: bounds.minY),
                options: []
            )
        }

        if let radialGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [accentSoft.cgColor, NSColor.clear.cgColor] as CFArray,
            locations: [0, 1]
        ) {
            context.drawRadialGradient(
                radialGradient,
                startCenter: CGPoint(x: bounds.width * 0.12, y: bounds.height * 0.16),
                startRadius: 20,
                endCenter: CGPoint(x: bounds.width * 0.12, y: bounds.height * 0.16),
                endRadius: min(bounds.width, bounds.height) * 0.42,
                options: []
            )
        }

        if let highlightGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [NSColor.white.withAlphaComponent(0.12).cgColor, NSColor.clear.cgColor] as CFArray,
            locations: [0, 1]
        ) {
            context.drawRadialGradient(
                highlightGradient,
                startCenter: CGPoint(x: bounds.width * 0.88, y: bounds.height * 0.88),
                startRadius: 10,
                endCenter: CGPoint(x: bounds.width * 0.88, y: bounds.height * 0.88),
                endRadius: min(bounds.width, bounds.height) * 0.24,
                options: []
            )
        }

        context.setFillColor(NSColor.white.withAlphaComponent(0.025).cgColor)
        context.fill(CGRect(x: bounds.minX, y: bounds.midY - 1, width: bounds.width, height: 2))
    }

    private func drawSafeBand(in context: CGContext) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bandRect = CGRect(x: 0, y: bounds.height - controlTop, width: bounds.width, height: controlTop)
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                NSColor.black.withAlphaComponent(0.46).cgColor,
                NSColor.clear.cgColor,
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: bandRect.minX, y: bandRect.maxY),
                end: CGPoint(x: bandRect.minX, y: bandRect.minY),
                options: []
            )
        }

        context.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
        context.fill(CGRect(x: 0, y: bandRect.minY, width: bounds.width, height: 1))
    }

    private func drawLiveLine(in context: CGContext, accent: NSColor, glow: NSColor) {
        let y = lineYPosition
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [NSColor.clear.cgColor, accent.cgColor, NSColor.clear.cgColor] as CFArray
        let locations: [CGFloat] = [0, 0.5, 1]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            let rect = CGRect(x: 0, y: y - 1, width: bounds.width, height: 2)
            context.saveGState()
            context.addRect(rect)
            context.clip()
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: y), end: CGPoint(x: bounds.width, y: y), options: [])
            context.restoreGState()
        }

        context.setFillColor(glow.withAlphaComponent(0.5).cgColor)
        context.fillEllipse(in: CGRect(x: bounds.width - min(bounds.width * 0.04, 28) - 9, y: y - 9, width: 18, height: 18))
        context.setFillColor(accent.cgColor)
        context.fillEllipse(in: CGRect(x: bounds.width - min(bounds.width * 0.04, 28) - 7, y: y - 7, width: 14, height: 14))
    }

    private func drawRail(in context: CGContext, accent: NSColor, glow: NSColor) {
        let railWidth = min(bounds.width * 0.08, 64)
        let trackHeight = min(bounds.height * 0.72, 620)
        let trackX = bounds.width - railWidth * 0.6
        let trackY = (bounds.height - trackHeight) / 2
        let knobY = trackY + trackHeight * CGFloat(snapshot.value) / 100

        context.setFillColor(NSColor.white.withAlphaComponent(0.14).cgColor)
        context.fill(CGRect(x: trackX, y: trackY, width: 2, height: trackHeight))

        let knobSize: CGFloat
        switch snapshot.interaction {
        case .dragging:
            knobSize = 32
        case .hovering:
            knobSize = 30
        case .idle:
            knobSize = 26
        }

        context.setFillColor(glow.withAlphaComponent(0.44).cgColor)
        context.fillEllipse(in: CGRect(x: trackX - knobSize / 2 - 4, y: knobY - knobSize / 2 - 4, width: knobSize + 8, height: knobSize + 8))
        context.setFillColor(accent.cgColor)
        context.fillEllipse(in: CGRect(x: trackX - knobSize / 2, y: knobY - knobSize / 2, width: knobSize, height: knobSize))
    }

    private func updateFromPointer(_ event: NSEvent, interaction: SurfaceInteraction) {
        let point = convert(event.locationInWindow, from: nil)
        if isPointInsideInteractiveControl(point) {
            if snapshot.hoverMode {
                controller.setHoverReady()
            }
            return
        }

        guard point.y <= controlHeight else {
            if snapshot.hoverMode {
                controller.setHoverReady()
            }
            return
        }

        let clampedY = min(max(point.y, 0), controlHeight)
        let value = Int((clampedY / max(controlHeight, 1) * 100).rounded())
        controller.setLiveValue(value, interaction: interaction)
    }

    private func isPointInsideInteractiveControl(_ point: CGPoint) -> Bool {
        guard let hitView = hitTest(point) else { return false }
        return hitView is NSButton || hitView.superview is NSButton
    }

    private var controlTop: CGFloat {
        min(max(bounds.height * 0.1, 64), 120)
    }

    private var controlHeight: CGFloat {
        max(bounds.height - controlTop, 1)
    }

    private var lineYPosition: CGFloat {
        controlHeight * CGFloat(snapshot.value) / 100
    }

    private func singleLineSize(for text: String, font: NSFont) -> CGSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private func multilineHeight(for text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(rect.height)
    }
}

final class PillButton: NSButton {
    var route: SurfaceRoute?

    override var acceptsFirstResponder: Bool { false }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 26
        size.height = 40
        return size
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = true
        font = NSFont.systemFont(ofSize: 14, weight: .bold)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func applyStyle(background: NSColor, text: NSColor) {
        layer?.backgroundColor = background.cgColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: text,
                .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            ]
        )
    }
}
