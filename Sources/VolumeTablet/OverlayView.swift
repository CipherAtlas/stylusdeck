import AppKit
import VolumeCore

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}

extension SurfaceRoute {
    func eyebrow(in bank: SurfaceBank) -> String {
        switch (bank, self) {
        case (.main, .volume): return "MAIN · VOLUME"
        case (.main, .low): return "MAIN · LOW BAND"
        case (.main, .mid): return "MAIN · MID BAND"
        case (.main, .high): return "MAIN · HIGH BAND"
        case (.fx, .volume): return "FX · FILTER"
        case (.fx, .low): return "FX · UNUSED"
        case (.fx, .mid): return "FX · UNUSED"
        case (.fx, .high): return "FX · ECHO"
        }
    }

    func navigationTitle(in bank: SurfaceBank) -> String {
        switch (bank, self) {
        case (.main, .volume): return "Volume"
        case (.main, .low): return "Low"
        case (.main, .mid): return "Mid"
        case (.main, .high): return "High"
        case (.fx, .volume): return "Filter"
        case (.fx, .low): return "Unused"
        case (.fx, .mid): return "Unused"
        case (.fx, .high): return "Echo"
        }
    }

    func metaText(in bank: SurfaceBank) -> String {
        switch (bank, self) {
        case (.main, .volume): return "Bank: Main · Path: Master"
        case (.main, .low): return "Bank: Main · Band: Low"
        case (.main, .mid): return "Bank: Main · Band: Mid"
        case (.main, .high): return "Bank: Main · Band: High"
        case (.fx, .volume): return "Bank: FX · Lane: Filter"
        case (.fx, .low): return "Bank: FX · Lane: Unused"
        case (.fx, .mid): return "Bank: FX · Lane: Unused"
        case (.fx, .high): return "Bank: FX · Lane: Echo"
        }
    }

    func primaryRangeText(in bank: SurfaceBank) -> String {
        switch (bank, self) {
        case (.main, .volume):
            return "Absolute Y position controls Mac output gain below the top safe band."
        case (.main, .low):
            return "Absolute Y position controls low-band gain below the top safe band."
        case (.main, .mid):
            return "Absolute Y position controls mid-band gain below the top safe band."
        case (.main, .high):
            return "Absolute Y position controls high-band gain below the top safe band."
        case (.fx, .volume):
            return "Absolute Y position sweeps the DJ filter macro around center."
        case (.fx, .low):
            return "This FX lane is intentionally unused."
        case (.fx, .mid):
            return "This FX lane is intentionally unused."
        case (.fx, .high):
            return "Absolute Y position controls echo wet mix."
        }
    }

    func accent(in bank: SurfaceBank) -> NSColor {
        switch (bank, self) {
        case (.main, .volume), (.fx, .volume):
            return NSColor(calibratedRed: 0.44, green: 0.94, blue: 0.76, alpha: 1)
        case (.main, .low), (.fx, .low):
            return NSColor(calibratedRed: 1.00, green: 0.61, blue: 0.42, alpha: 1)
        case (.main, .mid), (.fx, .mid):
            return NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.43, alpha: 1)
        case (.main, .high), (.fx, .high):
            return NSColor(calibratedRed: 0.48, green: 0.73, blue: 1.00, alpha: 1)
        }
    }

    func accentSoft(in bank: SurfaceBank) -> NSColor {
        accent(in: bank).withAlphaComponent(0.24)
    }

    func accentGlow(in bank: SurfaceBank) -> NSColor {
        accent(in: bank).withAlphaComponent(0.44)
    }

    var routeKey: String {
        switch self {
        case .volume: return "1"
        case .low: return "2"
        case .mid: return "3"
        case .high: return "4"
        }
    }

    func interactionText(in bank: SurfaceBank, for parameter: SurfaceParameter, hoverMode: Bool) -> String {
        let action = hoverMode ? "Hover" : "Drag"
        switch (bank, self, parameter) {
        case (.main, .volume, .primary):
            return "\(action) anywhere below the top safe band to raise or lower output gain."
        case (.main, .volume, .frequency):
            return "\(action) anywhere below the top safe band to trim the wet output before limiting."
        case (.main, .volume, .shape):
            return "\(action) anywhere below the top safe band to set limiter ceiling."
        case (.main, .low, .primary):
            return "\(action) anywhere below the top safe band to boost or cut the low band."
        case (.main, .mid, .primary):
            return "\(action) anywhere below the top safe band to boost or cut the mid band."
        case (.main, .high, .primary):
            return "\(action) anywhere below the top safe band to boost or cut the high band."
        case (.main, .low, .frequency):
            return "\(action) anywhere below the top safe band to move the low shelf frequency."
        case (.main, .mid, .frequency):
            return "\(action) anywhere below the top safe band to move the mid peak frequency."
        case (.main, .high, .frequency):
            return "\(action) anywhere below the top safe band to move the high shelf frequency."
        case (.main, .low, .shape):
            return "\(action) anywhere below the top safe band to change low shelf slope."
        case (.main, .mid, .shape):
            return "\(action) anywhere below the top safe band to change mid-band Q."
        case (.main, .high, .shape):
            return "\(action) anywhere below the top safe band to change high shelf slope."
        case (.fx, .volume, .primary):
            return "\(action) anywhere below the top safe band to sweep the DJ filter macro."
        case (.fx, .volume, .frequency):
            return "\(action) anywhere below the top safe band to change filter resonance."
        case (.fx, .volume, .shape):
            return "\(action) anywhere below the top safe band to change filter character."
        case (.fx, .low, _), (.fx, .mid, _):
            return "This FX lane is unused and will not change the sound."
        case (.fx, .high, .primary):
            return "\(action) anywhere below the top safe band to change echo wet mix."
        case (.fx, .high, .frequency):
            return "\(action) anywhere below the top safe band to change echo delay time."
        case (.fx, .high, .shape):
            return "\(action) anywhere below the top safe band to change echo feedback."
        }
    }

    func rangeText(in bank: SurfaceBank, for parameter: SurfaceParameter) -> String {
        switch (bank, self, parameter) {
        case (.main, .volume, .primary), (.main, .low, .primary), (.main, .mid, .primary), (.main, .high, .primary):
            return primaryRangeText(in: bank)
        case (.main, .volume, .frequency):
            return "X edits TRIM from -18 dB to +6 dB."
        case (.main, .volume, .shape):
            return "Shift+X edits CEILING from -6 dB to 0 dB."
        case (.main, .low, .frequency):
            return "X edits FREQ from 40 Hz to 240 Hz."
        case (.main, .mid, .frequency):
            return "X edits FREQ from 250 Hz to 5.0 kHz."
        case (.main, .high, .frequency):
            return "X edits FREQ from 4.0 kHz to 16.0 kHz."
        case (.main, .low, .shape), (.main, .high, .shape):
            return "Shift+X edits SLOPE from 0.50 to 1.20."
        case (.main, .mid, .shape):
            return "Shift+X edits Q from 0.50 to 2.00."
        case (.fx, .volume, .primary):
            return "Filter center is neutral. Down is high-pass, up is low-pass."
        case (.fx, .volume, .frequency):
            return "X edits RESO from 0.70 to 3.00."
        case (.fx, .volume, .shape):
            return "Shift+X edits CHAR from 0% to 100%."
        case (.fx, .low, _), (.fx, .mid, _):
            return "Unused lane. X and Y do nothing here."
        case (.fx, .high, .primary):
            return "Echo WET ranges from 0% to 70%."
        case (.fx, .high, .frequency):
            return "X edits TIME from 60 ms to 750 ms."
        case (.fx, .high, .shape):
            return "Shift+X edits FDBK from 0% to 82%."
        }
    }
}

enum SurfaceInteraction {
    case idle
    case dragging
    case hovering
}

enum VisualizerMode: String, CaseIterable {
    case waveRibbon
    case radialHalo
    case spectrumBars
    case orbitSphere

    var title: String {
        switch self {
        case .waveRibbon: return "Wave Ribbon"
        case .radialHalo: return "Radial Halo"
        case .spectrumBars: return "Spectrum Bars"
        case .orbitSphere: return "Orbit Sphere"
        }
    }
}

enum VisualizerPalette: String, CaseIterable {
    case ice
    case sunset
    case neonLime
    case chromeBlue
    case infrared
    case mono

    var title: String {
        switch self {
        case .ice: return "Ice"
        case .sunset: return "Sunset"
        case .neonLime: return "Neon Lime"
        case .chromeBlue: return "Chrome Blue"
        case .infrared: return "Infrared"
        case .mono: return "Monochrome"
        }
    }

    var colors: [NSColor] {
        switch self {
        case .ice:
            return [
                NSColor(calibratedRed: 0.42, green: 0.92, blue: 1.00, alpha: 1),
                NSColor(calibratedRed: 0.52, green: 0.73, blue: 1.00, alpha: 1),
                NSColor(calibratedRed: 0.89, green: 0.98, blue: 1.00, alpha: 1),
            ]
        case .sunset:
            return [
                NSColor(calibratedRed: 1.00, green: 0.49, blue: 0.36, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.32, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.32, blue: 0.53, alpha: 1),
            ]
        case .neonLime:
            return [
                NSColor(calibratedRed: 0.74, green: 1.00, blue: 0.35, alpha: 1),
                NSColor(calibratedRed: 0.18, green: 0.95, blue: 0.62, alpha: 1),
                NSColor(calibratedRed: 0.95, green: 1.00, blue: 0.78, alpha: 1),
            ]
        case .chromeBlue:
            return [
                NSColor(calibratedRed: 0.36, green: 0.76, blue: 1.00, alpha: 1),
                NSColor(calibratedRed: 0.36, green: 0.49, blue: 1.00, alpha: 1),
                NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.00, alpha: 1),
            ]
        case .infrared:
            return [
                NSColor(calibratedRed: 1.00, green: 0.20, blue: 0.26, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.50, blue: 0.18, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.88, blue: 0.44, alpha: 1),
            ]
        case .mono:
            return [
                NSColor(calibratedWhite: 0.96, alpha: 1),
                NSColor(calibratedWhite: 0.72, alpha: 1),
                NSColor(calibratedWhite: 0.42, alpha: 1),
            ]
        }
    }
}

struct VisualizerSettings {
    var enabled = false
    var mode: VisualizerMode = .waveRibbon
    var palette: VisualizerPalette = .ice
    var sensitivity: CGFloat = 1.15
    var smoothing: CGFloat = 0.78
    var glow: CGFloat = 0.72
    var trails: CGFloat = 0.62
    var density: CGFloat = 0.64
    var dim: CGFloat = 0.26
}

struct SurfaceSnapshot {
    var bank: SurfaceBank = .main
    var route: SurfaceRoute = .volume
    var parameter: SurfaceParameter = .primary
    var value: Int = 50
    var displayValue = "50%"
    var parameterLabel = "GAIN"
    var secondaryParameter: SurfaceParameter = .frequency
    var secondaryValue: Int = 75
    var secondaryDisplayValue = "0.0 dB"
    var secondaryParameterLabel = "TRIM"
    var hoverMode = false
    var interaction: SurfaceInteraction = .idle
    var statusText = "Loading"
    var backendName = "native-eq"
    var backendDetail = ""
    var connected = false
    var clipDetected = false
    var outputPeak: Float = 0
    var rmsLevel: Float = 0
    var lowEnergy: Float = 0
    var midEnergy: Float = 0
    var highEnergy: Float = 0
    var transient: Float = 0
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

@MainActor
final class ControlSurfaceController {
    private let bridge = EqBridgeClient()
    let state: ControlSurfaceState
    private let defaults = AudioControlState()
    private let activePollInterval: TimeInterval = 1.0 / 24.0
    private let idlePollInterval: TimeInterval = 0.25

    private var routeVersion = 0
    private var optionPressed = false
    private var shiftPressed = false
    private var pollingTimer: Timer?
    private var pollInterval: TimeInterval

    init(state: ControlSurfaceState) {
        self.state = state
        pollInterval = activePollInterval
    }

    func start() {
        refreshCurrentRoute()
        startPolling()
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        bridge.stop()
    }

    func navigate(to route: SurfaceRoute) {
        routeVersion += 1
        let version = routeVersion
        let bank = activeBank
        let parameter = activePrimaryParameter
        let secondaryParameter = activeSecondaryParameter(for: bank, route: route)
        state.update { snapshot in
            snapshot.bank = bank
            snapshot.route = route
            snapshot.parameter = parameter
            snapshot.secondaryParameter = secondaryParameter
            snapshot.interaction = .idle
            snapshot.statusText = "Loading"
        }

        let response = bridge.status(for: bank, route: route, parameter: parameter, secondaryParameter: secondaryParameter)
        guard version == routeVersion, state.snapshot.route == route, state.snapshot.bank == bank else { return }
        apply(response: response, updateStatus: true)
    }

    func refreshCurrentRoute() {
        let bank = activeBank
        let route = state.snapshot.route
        let parameter = activePrimaryParameter
        let secondaryParameter = activeSecondaryParameter(for: bank, route: route)
        let version = routeVersion
        let response = bridge.status(for: bank, route: route, parameter: parameter, secondaryParameter: secondaryParameter)
        guard version == routeVersion, state.snapshot.route == route, state.snapshot.bank == bank else { return }
        apply(response: response, updateStatus: true)
    }

    func toggleBank() {
        routeVersion += 1
        let version = routeVersion
        let nextBank: SurfaceBank = state.snapshot.bank == .main ? .fx : .main
        let route = state.snapshot.route
        let parameter = activePrimaryParameter
        let secondaryParameter = activeSecondaryParameter(for: nextBank, route: route)
        state.update { snapshot in
            snapshot.bank = nextBank
            snapshot.parameter = parameter
            snapshot.secondaryParameter = secondaryParameter
            snapshot.interaction = .idle
            snapshot.statusText = "Loading"
        }

        let response = bridge.status(for: nextBank, route: route, parameter: parameter, secondaryParameter: secondaryParameter)
        guard version == routeVersion, state.snapshot.route == route, state.snapshot.bank == nextBank else { return }
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
        let bank = activeBank
        let route = state.snapshot.route
        let secondaryParameter = activeSecondaryParameter(for: bank, route: route)
        let resetValue = defaults.descriptor(for: bank, route: route, parameter: .primary).defaultNormalizedValue
        let secondaryResetValue = defaults.descriptor(for: bank, route: route, parameter: secondaryParameter).defaultNormalizedValue
        setLivePoint(primaryValue: resetValue, secondaryValue: secondaryResetValue, interaction: .idle)
        state.update { snapshot in
            snapshot.statusText = "Centered"
        }
    }

    func setLivePoint(primaryValue: Int, secondaryValue: Int, interaction: SurfaceInteraction) {
        let clampedPrimary = max(0, min(100, primaryValue))
        let clampedSecondary = max(0, min(100, secondaryValue))
        let bank = activeBank
        let route = state.snapshot.route
        let secondaryParameter = activeSecondaryParameter(for: bank, route: route)
        let version = routeVersion

        state.update { snapshot in
            snapshot.bank = bank
            snapshot.parameter = .primary
            snapshot.secondaryParameter = secondaryParameter
            snapshot.value = clampedPrimary
            snapshot.secondaryValue = clampedSecondary
            snapshot.interaction = interaction
            snapshot.statusText = "Live"
        }

        let response = bridge.setGesture(
            primaryValue: clampedPrimary,
            secondaryValue: clampedSecondary,
            for: bank,
            route: route,
            secondaryParameter: secondaryParameter
        )
        guard version == routeVersion, state.snapshot.route == route, state.snapshot.bank == bank else { return }
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

    func updateModifierFlags(_ flags: NSEvent.ModifierFlags) {
        let nextOption = flags.contains(.option)
        let nextShift = flags.contains(.shift)
        guard nextOption != optionPressed || nextShift != shiftPressed else { return }
        optionPressed = nextOption
        shiftPressed = nextShift
        refreshCurrentRoute()
    }

    func setVisualizerMonitoringEnabled(_ enabled: Bool) {
        let nextInterval = enabled ? activePollInterval : idlePollInterval
        guard abs(nextInterval - pollInterval) > 0.0001 else { return }
        pollInterval = nextInterval
        if pollingTimer != nil {
            startPolling()
        }
    }

    private func apply(response: EqBridgeResponse, updateStatus: Bool) {
        state.update { snapshot in
            snapshot.bank = response.bank ?? snapshot.bank
            snapshot.parameter = response.parameter ?? snapshot.parameter
            if let value = response.value {
                snapshot.value = value
            }
            if let displayValue = response.displayValue {
                snapshot.displayValue = displayValue
            }
            if let parameterLabel = response.parameterLabel {
                snapshot.parameterLabel = parameterLabel
            }
            snapshot.secondaryParameter = response.secondaryParameter ?? snapshot.secondaryParameter
            if let secondaryValue = response.secondaryValue {
                snapshot.secondaryValue = secondaryValue
            }
            if let secondaryDisplayValue = response.secondaryDisplayValue {
                snapshot.secondaryDisplayValue = secondaryDisplayValue
            }
            if let secondaryParameterLabel = response.secondaryParameterLabel {
                snapshot.secondaryParameterLabel = secondaryParameterLabel
            }
            snapshot.connected = response.connected
            snapshot.backendName = response.backend
            snapshot.backendDetail = response.detail
            snapshot.clipDetected = response.clipDetected
            snapshot.outputPeak = response.outputPeak ?? snapshot.outputPeak
            snapshot.rmsLevel = response.rmsLevel ?? snapshot.rmsLevel
            snapshot.lowEnergy = response.lowEnergy ?? snapshot.lowEnergy
            snapshot.midEnergy = response.midEnergy ?? snapshot.midEnergy
            snapshot.highEnergy = response.highEnergy ?? snapshot.highEnergy
            snapshot.transient = response.transient ?? snapshot.transient
            if updateStatus {
                snapshot.statusText = snapshot.hoverMode ? "Hover ready" : "Drag ready"
            }
        }
    }

    private var activeBank: SurfaceBank {
        state.snapshot.bank
    }

    private var activePrimaryParameter: SurfaceParameter {
        .primary
    }

    private func activeSecondaryParameter(for bank: SurfaceBank, route: SurfaceRoute) -> SurfaceParameter {
        defaults.pointerSecondaryParameter(for: bank, route: route, shiftPressed: shiftPressed)
    }

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentRoute()
            }
        }
        if let pollingTimer {
            RunLoop.main.add(pollingTimer, forMode: .common)
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
    private let bankButton = PillButton()
    private let visualsButton = PillButton()
    private let modeButton = PillButton()
    private let fullscreenButton = PillButton()
    private let centerButton = PillButton()
    private let routeButtons = SurfaceRoute.allCases.reduce(into: [SurfaceRoute: PillButton]()) { partialResult, route in
        partialResult[route] = PillButton()
    }

    private let eyebrowLabel = NSTextField(labelWithString: "")
    private let parameterLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let secondaryParameterLabel = NSTextField(labelWithString: "")
    private let secondaryValueLabel = NSTextField(labelWithString: "")
    private let subcopyLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let rangeNoteLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let clipBadgeLabel = NSTextField(labelWithString: "CLIP")

    private let settingsPanel = NSVisualEffectView()
    private let settingsTitleLabel = NSTextField(labelWithString: "Visualizer")
    private let enabledToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let palettePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sensitivitySlider = NSSlider(value: 1.15, minValue: 0.6, maxValue: 2.0, target: nil, action: nil)
    private let smoothingSlider = NSSlider(value: 0.78, minValue: 0.2, maxValue: 0.95, target: nil, action: nil)
    private let glowSlider = NSSlider(value: 0.72, minValue: 0.1, maxValue: 1.0, target: nil, action: nil)
    private let trailSlider = NSSlider(value: 0.62, minValue: 0.1, maxValue: 1.0, target: nil, action: nil)
    private let densitySlider = NSSlider(value: 0.64, minValue: 0.2, maxValue: 1.0, target: nil, action: nil)
    private let dimSlider = NSSlider(value: 0.26, minValue: 0.0, maxValue: 0.7, target: nil, action: nil)

    private var trackingAreaRef: NSTrackingArea?
    private var snapshot = SurfaceSnapshot()
    private var visualizerSettings = VisualizerSettings()
    private var settingsPanelVisible = false
    private var animationTimer: Timer?
    private var smoothedRMS: CGFloat = 0
    private var smoothedLow: CGFloat = 0
    private var smoothedMid: CGFloat = 0
    private var smoothedHigh: CGFloat = 0
    private var smoothedTransient: CGFloat = 0
    private var visualizerPhase: CGFloat = 0
    private var waveHistory: [CGFloat] = Array(repeating: 0, count: 96)
    private var lowHistory: [CGFloat] = Array(repeating: 0, count: 48)
    private var midHistory: [CGFloat] = Array(repeating: 0, count: 48)
    private var highHistory: [CGFloat] = Array(repeating: 0, count: 48)

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
        setupSettingsPanel()
        installSubviews()
        updateVisualizerPerformanceMode()
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard settingsPanelVisible else {
            return super.hitTest(point)
        }

        if let hitView = super.hitTest(point) {
            if hitView == settingsPanel || hitView.isDescendant(of: settingsPanel) {
                return hitView
            }
        }

        return bounds.contains(point) ? self : nil
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
        let bank = snapshot.bank

        drawBackground(in: context, accent: route.accent(in: bank), accentSoft: route.accentSoft(in: bank))
        if visualizerSettings.enabled {
            drawVisualizer(in: context)
        }
        drawSafeBand(in: context)
        drawLiveLine(in: context, accent: route.accent(in: bank), glow: route.accentGlow(in: bank))
        drawVerticalRail(in: context, accent: route.accent(in: bank), glow: route.accentGlow(in: bank))
        drawHorizontalRail(in: context, accent: route.accent(in: bank), glow: route.accentGlow(in: bank))
    }

    override func mouseDown(with event: NSEvent) {
        if settingsPanelVisible {
            let point = convert(event.locationInWindow, from: nil)
            if !isPointInsideSettingsPanel(point) {
                closeSettingsPanel()
            }
            return
        }
        guard !snapshot.hoverMode else { return }
        controller.updateModifierFlags(event.modifierFlags)
        updateFromPointer(event, interaction: .dragging)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !settingsPanelVisible else { return }
        guard !snapshot.hoverMode else { return }
        controller.updateModifierFlags(event.modifierFlags)
        updateFromPointer(event, interaction: .dragging)
    }

    override func mouseUp(with event: NSEvent) {
        controller.endDrag()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !settingsPanelVisible else {
            controller.setHoverReady()
            return
        }
        guard snapshot.hoverMode else { return }
        controller.updateModifierFlags(event.modifierFlags)
        updateFromPointer(event, interaction: .hovering)
    }

    override func mouseExited(with event: NSEvent) {
        controller.setHoverReady()
    }

    override func tabletPoint(with event: NSEvent) {
        guard !settingsPanelVisible else {
            controller.setHoverReady()
            return
        }
        if snapshot.hoverMode || event.pressure > 0 {
            controller.updateModifierFlags(event.modifierFlags)
            updateFromPointer(event, interaction: snapshot.hoverMode ? .hovering : .dragging)
        }
    }

    override func pressureChange(with event: NSEvent) {
        guard !settingsPanelVisible else {
            controller.endDrag()
            return
        }
        controller.updateModifierFlags(event.modifierFlags)
        if event.pressure > 0 {
            updateFromPointer(event, interaction: snapshot.hoverMode ? .hovering : .dragging)
        } else if snapshot.hoverMode {
            controller.setHoverReady()
        } else {
            controller.endDrag()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        controller.updateModifierFlags(event.modifierFlags)
    }

    override func rightMouseDown(with event: NSEvent) {
        if settingsPanelVisible {
            let point = convert(event.locationInWindow, from: nil)
            if !isPointInsideSettingsPanel(point) {
                closeSettingsPanel()
            }
            return
        }
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
    private func handleBankButton() {
        controller.toggleBank()
        window?.makeFirstResponder(self)
    }

    @objc
    private func handleVisualsButton() {
        setSettingsPanelVisible(!settingsPanelVisible)
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

        bankButton.target = self
        bankButton.action = #selector(handleBankButton)

        visualsButton.target = self
        visualsButton.action = #selector(handleVisualsButton)

        modeButton.target = self
        modeButton.action = #selector(handleModeButton)

        fullscreenButton.target = self
        fullscreenButton.action = #selector(handleFullscreenButton)

        centerButton.target = self
        centerButton.action = #selector(handleCenterButton)

        bankButton.title = "Bank: Main"
        visualsButton.title = "Visuals"
        modeButton.title = "Mode: Drag"
        fullscreenButton.title = "Fullscreen"
        centerButton.title = "Center"

        [bankButton, visualsButton, modeButton, fullscreenButton, centerButton].forEach {
            actionsStack.addArrangedSubview($0)
        }

        for route in SurfaceRoute.allCases {
            if let button = routeButtons[route] {
                button.route = route
                button.title = route.navigationTitle(in: .main)
                button.target = self
                button.action = #selector(handleRouteButton(_:))
                navStack.addArrangedSubview(button)
            }
        }
    }

    private func setupLabels() {
        [brandNameLabel, eyebrowLabel, parameterLabel, valueLabel, secondaryParameterLabel, secondaryValueLabel, subcopyLabel, metaLabel, rangeNoteLabel, statusLabel].forEach { label in
            label.isBordered = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            addSubview(label)
        }

        brandNameLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        eyebrowLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        parameterLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        valueLabel.textColor = .white
        secondaryParameterLabel.textColor = NSColor.white.withAlphaComponent(0.64)
        secondaryValueLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        subcopyLabel.textColor = NSColor.white.withAlphaComponent(0.82)
        metaLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        rangeNoteLabel.textColor = NSColor.white.withAlphaComponent(0.52)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.68)

        eyebrowLabel.alignment = .left
        parameterLabel.alignment = .left
        valueLabel.alignment = .left
        secondaryParameterLabel.alignment = .left
        secondaryValueLabel.alignment = .left
        subcopyLabel.alignment = .left
        metaLabel.alignment = .left
        rangeNoteLabel.alignment = .left
        statusLabel.alignment = .right
    }

    private func setupSettingsPanel() {
        settingsPanel.material = .hudWindow
        settingsPanel.blendingMode = .withinWindow
        settingsPanel.state = .active
        settingsPanel.wantsLayer = true
        settingsPanel.layer?.cornerRadius = 28
        settingsPanel.layer?.borderWidth = 1
        settingsPanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        settingsTitleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        settingsTitleLabel.textColor = .white

        enabledToggle.setButtonType(.switch)
        enabledToggle.title = ""
        enabledToggle.target = self
        enabledToggle.action = #selector(handleEnabledToggle)

        configurePopup(modePopup, titles: VisualizerMode.allCases.map(\.title), action: #selector(handleModeSelection))
        configurePopup(palettePopup, titles: VisualizerPalette.allCases.map(\.title), action: #selector(handlePaletteSelection))
        configureSlider(sensitivitySlider, action: #selector(handleSliderChange(_:)))
        configureSlider(smoothingSlider, action: #selector(handleSliderChange(_:)))
        configureSlider(glowSlider, action: #selector(handleSliderChange(_:)))
        configureSlider(trailSlider, action: #selector(handleSliderChange(_:)))
        configureSlider(densitySlider, action: #selector(handleSliderChange(_:)))
        configureSlider(dimSlider, action: #selector(handleSliderChange(_:)))

        [settingsTitleLabel, makeSettingsRow(title: "Visualizer", control: enabledToggle), makeSettingsRow(title: "Mode", control: modePopup), makeSettingsRow(title: "Palette", control: palettePopup), makeSettingsRow(title: "Energy", control: sensitivitySlider), makeSettingsRow(title: "Smooth", control: smoothingSlider), makeSettingsRow(title: "Glow", control: glowSlider), makeSettingsRow(title: "Trails", control: trailSlider), makeSettingsRow(title: "Density", control: densitySlider), makeSettingsRow(title: "Dim", control: dimSlider)].forEach {
            settingsPanel.addSubview($0)
        }

        clipBadgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        clipBadgeLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.36, alpha: 1)
        clipBadgeLabel.alignment = .center
        clipBadgeLabel.isHidden = true
        addSubview(clipBadgeLabel)
    }

    private func setupBranding() {
        brandMarkView.image = BrandAssets.markImage()
        brandMarkView.imageScaling = .scaleProportionallyUpOrDown
        brandMarkView.alphaValue = 0.88
        addSubview(brandMarkView)
    }

    private func installSubviews() {
        addSubview(actionsStack)
        addSubview(navStack)
        addSubview(settingsPanel)
    }

    private func startAnimationLoop() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceVisualizer()
            }
        }
        if let animationTimer {
            RunLoop.main.add(animationTimer, forMode: .common)
        }
    }

    private func refreshFromState() {
        let previous = snapshot
        snapshot = state.snapshot
        let layoutChanged =
            previous.bank != snapshot.bank ||
            previous.route != snapshot.route ||
            previous.hoverMode != snapshot.hoverMode ||
            previous.interaction != snapshot.interaction ||
            previous.value != snapshot.value ||
            previous.displayValue != snapshot.displayValue ||
            previous.parameterLabel != snapshot.parameterLabel ||
            previous.secondaryValue != snapshot.secondaryValue ||
            previous.secondaryDisplayValue != snapshot.secondaryDisplayValue ||
            previous.secondaryParameterLabel != snapshot.secondaryParameterLabel ||
            previous.clipDetected != snapshot.clipDetected

        if layoutChanged {
            updateButtonStyles()
            updateLabels()
            needsLayout = true
        }

        if previous.outputPeak != snapshot.outputPeak ||
            previous.rmsLevel != snapshot.rmsLevel ||
            previous.lowEnergy != snapshot.lowEnergy ||
            previous.midEnergy != snapshot.midEnergy ||
            previous.highEnergy != snapshot.highEnergy ||
            previous.transient != snapshot.transient ||
            layoutChanged {
            needsDisplay = layoutChanged || visualizerSettings.enabled
        }
    }

    private func setSettingsPanelVisible(_ visible: Bool) {
        settingsPanelVisible = visible
        if visible {
            controller.endDrag()
        }
        syncSettingsControls()
        updateButtonStyles()
        needsLayout = true
        needsDisplay = true
    }

    private func closeSettingsPanel() {
        guard settingsPanelVisible else { return }
        setSettingsPanelVisible(false)
    }

    private func updateVisualizerPerformanceMode() {
        controller.setVisualizerMonitoringEnabled(visualizerSettings.enabled)
        if visualizerSettings.enabled {
            startAnimationLoop()
        } else {
            stopAnimationLoop()
        }
    }

    private func advanceVisualizer() {
        clipBadgeLabel.isHidden = !snapshot.clipDetected
        guard visualizerSettings.enabled else { return }

        let responseBlend = 1 - visualizerSettings.smoothing
        smoothedRMS += (CGFloat(snapshot.rmsLevel) * visualizerSettings.sensitivity - smoothedRMS) * responseBlend
        smoothedLow += (CGFloat(snapshot.lowEnergy) * visualizerSettings.sensitivity - smoothedLow) * responseBlend
        smoothedMid += (CGFloat(snapshot.midEnergy) * visualizerSettings.sensitivity - smoothedMid) * responseBlend
        smoothedHigh += (CGFloat(snapshot.highEnergy) * visualizerSettings.sensitivity - smoothedHigh) * responseBlend
        smoothedTransient += (CGFloat(snapshot.transient) * visualizerSettings.sensitivity - smoothedTransient) * max(0.18, responseBlend * 1.6)

        visualizerPhase += 0.022 + smoothedHigh * 0.035 + smoothedTransient * 0.02
        shiftHistory(&waveHistory, next: smoothedRMS + smoothedTransient * 0.35)
        shiftHistory(&lowHistory, next: smoothedLow)
        shiftHistory(&midHistory, next: smoothedMid)
        shiftHistory(&highHistory, next: smoothedHigh)
        clipBadgeLabel.isHidden = !snapshot.clipDetected
        needsDisplay = true
    }

    private func shiftHistory(_ history: inout [CGFloat], next: CGFloat) {
        guard !history.isEmpty else { return }
        history.removeFirst()
        history.append(max(0, min(1.25, next)))
    }

    private func stopAnimationLoop() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func configurePopup(_ popup: NSPopUpButton, titles: [String], action: Selector) {
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
        popup.target = self
        popup.action = action
        popup.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    }

    private func configureSlider(_ slider: NSSlider, action: Selector) {
        slider.target = self
        slider.action = action
        slider.controlSize = .small
    }

    private func makeSettingsRow(title: String, control: NSView) -> NSView {
        let container = NSView(frame: .zero)
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.78)
        label.frame = NSRect(x: 0, y: 18, width: 90, height: 16)
        control.frame = NSRect(x: 94, y: 0, width: 180, height: 34)
        container.addSubview(label)
        container.addSubview(control)
        return container
    }

    private func syncSettingsControls() {
        enabledToggle.state = visualizerSettings.enabled ? .on : .off
        modePopup.selectItem(at: VisualizerMode.allCases.firstIndex(of: visualizerSettings.mode) ?? 0)
        palettePopup.selectItem(at: VisualizerPalette.allCases.firstIndex(of: visualizerSettings.palette) ?? 0)
        sensitivitySlider.doubleValue = visualizerSettings.sensitivity
        smoothingSlider.doubleValue = visualizerSettings.smoothing
        glowSlider.doubleValue = visualizerSettings.glow
        trailSlider.doubleValue = visualizerSettings.trails
        densitySlider.doubleValue = visualizerSettings.density
        dimSlider.doubleValue = visualizerSettings.dim
    }

    private func layoutSettingsPanel() {
        guard settingsPanel.subviews.count >= 2 else { return }
        settingsTitleLabel.frame = NSRect(x: 22, y: settingsPanel.bounds.height - 36, width: settingsPanel.bounds.width - 44, height: 22)
        let rows = settingsPanel.subviews.dropFirst()
        var y = settingsPanel.bounds.height - 78
        for row in rows {
            row.frame = NSRect(x: 22, y: y, width: settingsPanel.bounds.width - 44, height: 34)
            if let toggle = row.subviews.compactMap({ $0 as? NSButton }).first, toggle == enabledToggle {
                toggle.frame = NSRect(x: row.bounds.width - 34, y: 4, width: 26, height: 24)
            }
            if let popup = row.subviews.compactMap({ $0 as? NSPopUpButton }).first {
                popup.frame = NSRect(x: row.bounds.width - 170, y: 0, width: 170, height: 30)
            }
            if let slider = row.subviews.compactMap({ $0 as? NSSlider }).first {
                slider.frame = NSRect(x: row.bounds.width - 170, y: 4, width: 170, height: 24)
            }
            y -= 42
        }
    }

    @objc
    private func handleEnabledToggle() {
        visualizerSettings.enabled = enabledToggle.state == .on
        updateVisualizerPerformanceMode()
        needsDisplay = true
    }

    @objc
    private func handleModeSelection() {
        visualizerSettings.mode = VisualizerMode.allCases[safe: modePopup.indexOfSelectedItem] ?? .waveRibbon
        needsDisplay = true
    }

    @objc
    private func handlePaletteSelection() {
        visualizerSettings.palette = VisualizerPalette.allCases[safe: palettePopup.indexOfSelectedItem] ?? .ice
        needsDisplay = true
    }

    @objc
    private func handleSliderChange(_ sender: NSSlider) {
        switch sender {
        case sensitivitySlider:
            visualizerSettings.sensitivity = CGFloat(sender.doubleValue)
        case smoothingSlider:
            visualizerSettings.smoothing = CGFloat(sender.doubleValue)
        case glowSlider:
            visualizerSettings.glow = CGFloat(sender.doubleValue)
        case trailSlider:
            visualizerSettings.trails = CGFloat(sender.doubleValue)
        case densitySlider:
            visualizerSettings.density = CGFloat(sender.doubleValue)
        case dimSlider:
            visualizerSettings.dim = CGFloat(sender.doubleValue)
        default:
            break
        }
        needsDisplay = true
    }

    private func updateButtonStyles() {
        let accent = snapshot.route.accent(in: snapshot.bank)
        bankButton.title = "Bank: \(snapshot.bank == .main ? "Main" : "FX")"
        modeButton.title = "Mode: \(snapshot.hoverMode ? "Hover" : "Drag")"

        bankButton.applyStyle(background: NSColor.white.withAlphaComponent(0.10), text: .white)
        visualsButton.applyStyle(
            background: settingsPanelVisible ? accent : NSColor.white.withAlphaComponent(0.10),
            text: settingsPanelVisible ? NSColor(calibratedWhite: 0.06, alpha: 1) : .white
        )
        modeButton.applyStyle(background: NSColor.white.withAlphaComponent(0.10), text: .white)
        fullscreenButton.applyStyle(background: accent, text: NSColor(calibratedWhite: 0.06, alpha: 1))
        centerButton.applyStyle(background: NSColor.white.withAlphaComponent(0.10), text: .white)

        for route in SurfaceRoute.allCases {
            guard let button = routeButtons[route] else { continue }
            button.title = route.navigationTitle(in: snapshot.bank)
            if route == snapshot.route {
                button.applyStyle(background: accent, text: NSColor(calibratedWhite: 0.06, alpha: 1))
            } else {
                button.applyStyle(background: NSColor.white.withAlphaComponent(0.10), text: .white)
            }
        }
    }

    private func updateLabels() {
        let route = snapshot.route
        let isInactiveFXLane = snapshot.bank == .fx && (route == .low || route == .mid)

        eyebrowLabel.stringValue = route.eyebrow(in: snapshot.bank)
        parameterLabel.stringValue = "Y · \(snapshot.parameterLabel)"
        valueLabel.stringValue = snapshot.displayValue
        secondaryParameterLabel.stringValue = "X · \(snapshot.secondaryParameterLabel)"
        secondaryValueLabel.stringValue = snapshot.secondaryDisplayValue
        subcopyLabel.stringValue = isInactiveFXLane ? "" : ""
        rangeNoteLabel.stringValue = ""
        metaLabel.stringValue = ""
        statusLabel.stringValue = ""
        clipBadgeLabel.isHidden = !snapshot.clipDetected
    }

    private func metaString() -> String {
        let backend = snapshot.connected ? snapshot.backendName.uppercased() : "\(snapshot.backendName.uppercased()) · NOT CONNECTED"
        if snapshot.backendDetail.isEmpty {
            return "\(snapshot.route.metaText(in: snapshot.bank)) · \(backend)"
        }
        return "\(snapshot.route.metaText(in: snapshot.bank)) · \(backend) · \(snapshot.backendDetail)"
    }

    private func layoutTopBars() {
        let paddingX: CGFloat = 34
        let paddingY: CGFloat = 28

        actionsStack.setFrameSize(actionsStack.fittingSize)
        navStack.setFrameSize(navStack.fittingSize)

        actionsStack.frame.origin = NSPoint(
            x: paddingX,
            y: bounds.height - paddingY - actionsStack.frame.height
        )

        navStack.frame.origin = NSPoint(
            x: bounds.width - paddingX - navStack.frame.width,
            y: bounds.height - paddingY - navStack.frame.height
        )
        clipBadgeLabel.frame = NSRect(x: bounds.width - paddingX - 72, y: actionsStack.frame.minY + 4, width: 56, height: 22)

        let panelWidth = min(max(bounds.width * 0.24, 280), 360)
        let panelHeight: CGFloat = 404
        let panelX = bounds.width - paddingX - panelWidth
        let panelY = navStack.frame.minY - panelHeight - 18
        settingsPanel.frame = NSRect(x: panelX, y: max(28, panelY), width: panelWidth, height: panelHeight)
        settingsPanel.isHidden = !settingsPanelVisible
        layoutSettingsPanel()
    }

    private func layoutHero() {
        let paddingX: CGFloat = 34
        let heroOriginX = paddingX
        let heroTop = bounds.height * 0.6

        let brandMarkSize = min(max(bounds.width * 0.05, 52), 72)
        eyebrowLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        parameterLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        brandNameLabel.font = NSFont.systemFont(ofSize: min(bounds.width * 0.024, 28), weight: .semibold)
        valueLabel.font = NSFont.systemFont(ofSize: min(bounds.width * 0.18, 186), weight: .black)
        secondaryParameterLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        secondaryValueLabel.font = NSFont.systemFont(ofSize: min(bounds.width * 0.038, 32), weight: .bold)

        brandMarkView.frame = NSRect(
            x: heroOriginX,
            y: bounds.height - controlTop - brandMarkSize - 20,
            width: brandMarkSize,
            height: brandMarkSize
        )

        brandNameLabel.frame = .zero

        let eyebrowY = brandMarkView.frame.minY - 18
        eyebrowLabel.frame = NSRect(
            x: heroOriginX,
            y: eyebrowY,
            width: 220,
            height: 18
        )

        parameterLabel.frame = NSRect(
            x: heroOriginX,
            y: eyebrowLabel.frame.minY - 18,
            width: 240,
            height: 20
        )

        let valueSize = singleLineSize(for: valueLabel.stringValue, font: valueLabel.font ?? .systemFont(ofSize: 160))
        let valueY = min(heroTop + 18, parameterLabel.frame.minY - valueSize.height - 10)
        valueLabel.frame = NSRect(x: heroOriginX, y: valueY, width: valueSize.width + 8, height: valueSize.height + 8)

        secondaryParameterLabel.frame = NSRect(
            x: heroOriginX,
            y: valueLabel.frame.minY - 18,
            width: 220,
            height: 18
        )

        let secondaryValueSize = singleLineSize(
            for: secondaryValueLabel.stringValue,
            font: secondaryValueLabel.font ?? .systemFont(ofSize: 28)
        )
        secondaryValueLabel.frame = NSRect(
            x: heroOriginX,
            y: secondaryParameterLabel.frame.minY - secondaryValueSize.height - 4,
            width: secondaryValueSize.width + 8,
            height: secondaryValueSize.height + 6
        )

        statusLabel.frame = .zero
        metaLabel.frame = .zero
        rangeNoteLabel.frame = .zero
        subcopyLabel.frame = .zero
    }

    private func layoutFooter() {
        statusLabel.frame = .zero
        metaLabel.frame = .zero
        rangeNoteLabel.frame = .zero
        subcopyLabel.frame = .zero
    }

    private func drawBackground(in context: CGContext, accent: NSColor, accentSoft: NSColor) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let palette = visualizerSettings.palette.colors
        let topColor = palette[1].withAlphaComponent(0.12).blended(withFraction: 0.85, of: NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.04, alpha: 1))!.cgColor
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
        context.setFillColor(NSColor.black.withAlphaComponent(visualizerSettings.dim).cgColor)
        context.fill(bounds)
    }

    private func drawVisualizer(in context: CGContext) {
        let palette = visualizerSettings.palette.colors
        switch visualizerSettings.mode {
        case .waveRibbon:
            drawWaveRibbon(in: context, palette: palette)
        case .radialHalo:
            drawRadialHalo(in: context, palette: palette)
        case .spectrumBars:
            drawSpectrumBars(in: context, palette: palette)
        case .orbitSphere:
            drawOrbitSphere(in: context, palette: palette)
        }
    }

    private func drawWaveRibbon(in context: CGContext, palette: [NSColor]) {
        let baseline = bounds.midY
        let amplitude = bounds.height * (0.18 + smoothedRMS * 0.16)
        let density = max(18, Int(36 + visualizerSettings.density * 84))
        let path = NSBezierPath()
        for index in 0..<density {
            let ratio = CGFloat(index) / CGFloat(max(density - 1, 1))
            let x = bounds.minX + ratio * bounds.width
            let historyIndex = min(waveHistory.count - 1, Int(ratio * CGFloat(max(waveHistory.count - 1, 1))))
            let energy = waveHistory[historyIndex]
            let harmonic = sin(visualizerPhase * 1.7 + ratio * 9.5) * (0.35 + smoothedHigh * 0.6)
            let y = baseline + (energy * amplitude + harmonic * amplitude * 0.34) * sin(ratio * .pi * 2 + visualizerPhase * 0.6)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.line(to: CGPoint(x: x, y: y))
            }
        }
        drawGlowPath(path, in: context, color: palette[0], width: 4 + visualizerSettings.glow * 6)
        drawGlowPath(path, in: context, color: palette[1].withAlphaComponent(0.72), width: 1.8 + visualizerSettings.glow * 2.2)
    }

    private func drawRadialHalo(in context: CGContext, palette: [NSColor]) {
        let center = CGPoint(x: bounds.width * 0.56, y: bounds.height * 0.5)
        let baseRadius = min(bounds.width, bounds.height) * 0.15
        let points = max(42, Int(72 + visualizerSettings.density * 64))
        let path = NSBezierPath()
        for index in 0...points {
            let ratio = CGFloat(index) / CGFloat(points)
            let angle = ratio * .pi * 2
            let wave = sin(angle * 6 + visualizerPhase * 2.4) * smoothedHigh * 18
            let bump = cos(angle * 3 - visualizerPhase * 1.7) * smoothedLow * 28
            let transientLift = smoothedTransient * 44
            let radius = baseRadius + wave + bump + transientLift
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()
        context.setFillColor(palette[1].withAlphaComponent(0.08 + visualizerSettings.trails * 0.08).cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        drawGlowPath(path, in: context, color: palette[0], width: 2.4 + visualizerSettings.glow * 5.2)
    }

    private func drawSpectrumBars(in context: CGContext, palette: [NSColor]) {
        let barCount = max(18, Int(24 + visualizerSettings.density * 72))
        let availableWidth = bounds.width * 0.74
        let startX = bounds.midX - availableWidth / 2
        let barWidth = availableWidth / CGFloat(barCount) * 0.62
        let spacing = availableWidth / CGFloat(barCount)
        let maxHeight = bounds.height * 0.36
        for index in 0..<barCount {
            let ratio = CGFloat(index) / CGFloat(max(barCount - 1, 1))
            let low = interpolatedHistory(lowHistory, ratio: ratio)
            let mid = interpolatedHistory(midHistory, ratio: ratio)
            let high = interpolatedHistory(highHistory, ratio: ratio)
            let energy = low * 0.44 + mid * 0.34 + high * 0.22 + smoothedTransient * 0.18
            let height = maxHeight * max(0.04, energy)
            let x = startX + CGFloat(index) * spacing
            let rect = CGRect(x: x, y: bounds.midY - height / 2, width: barWidth, height: height)
            let color = blendPalette(palette: palette, ratio: ratio).withAlphaComponent(0.16 + 0.64 * energy)
            context.setFillColor(color.cgColor)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
            context.fillPath()
        }
    }

    private func drawOrbitSphere(in context: CGContext, palette: [NSColor]) {
        let center = CGPoint(x: bounds.width * 0.54, y: bounds.height * 0.52)
        let sphereRadius = min(bounds.width, bounds.height) * (0.11 + smoothedRMS * 0.02)
        let lineCount = max(36, Int(54 + visualizerSettings.density * 72))
        let coreRect = CGRect(
            x: center.x - sphereRadius,
            y: center.y - sphereRadius,
            width: sphereRadius * 2,
            height: sphereRadius * 2
        )

        let coreGradientColors = [palette[2].withAlphaComponent(0.20).cgColor, palette[0].withAlphaComponent(0.06).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: coreGradientColors, locations: [0, 1]) {
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 6,
                endCenter: center,
                endRadius: sphereRadius * (1.55 + visualizerSettings.glow * 0.3),
                options: []
            )
        }

        context.saveGState()
        context.setShadow(offset: .zero, blur: 22 + visualizerSettings.glow * 26, color: palette[0].withAlphaComponent(0.34).cgColor)
        context.setFillColor(palette[1].withAlphaComponent(0.11 + smoothedRMS * 0.08).cgColor)
        context.fillEllipse(in: coreRect)
        context.restoreGState()

        context.setStrokeColor(palette[2].withAlphaComponent(0.26 + smoothedRMS * 0.18).cgColor)
        context.setLineWidth(1.2)
        context.strokeEllipse(in: coreRect.insetBy(dx: sphereRadius * 0.08, dy: sphereRadius * 0.08))

        context.setLineCap(.round)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 10 + visualizerSettings.glow * 18, color: palette[0].withAlphaComponent(0.22).cgColor)
        for index in 0..<lineCount {
            let ratio = CGFloat(index) / CGFloat(max(lineCount, 1))
            let angle = ratio * .pi * 2
            let historyEnergy = interpolatedHistory(highHistory, ratio: ratio) * 0.42 +
                interpolatedHistory(midHistory, ratio: ratio) * 0.35 +
                interpolatedHistory(lowHistory, ratio: ratio) * 0.23
            let pulse = sin(visualizerPhase * 1.6 + ratio * 10.0) * (0.08 + smoothedTransient * 0.3)
            let lineLength = sphereRadius * (0.22 + historyEnergy * 1.55 + pulse)

            let start = CGPoint(
                x: center.x + cos(angle) * sphereRadius * 0.92,
                y: center.y + sin(angle) * sphereRadius * 0.92
            )
            let control = CGPoint(
                x: center.x + cos(angle + sin(visualizerPhase + ratio * 5) * 0.12) * (sphereRadius + lineLength * 0.52),
                y: center.y + sin(angle + cos(visualizerPhase + ratio * 4) * 0.12) * (sphereRadius + lineLength * 0.52)
            )
            let end = CGPoint(
                x: center.x + cos(angle) * (sphereRadius + lineLength),
                y: center.y + sin(angle) * (sphereRadius + lineLength)
            )

            let path = NSBezierPath()
            path.move(to: start)
            path.curve(to: end, controlPoint1: control, controlPoint2: control)
            let color = blendPalette(palette: palette, ratio: ratio).withAlphaComponent(0.28 + historyEnergy * 0.44)
            color.setStroke()
            path.lineWidth = 0.8 + historyEnergy * 1.8
            path.stroke()
        }
        context.restoreGState()

        let orbitCount = 12
        for index in 0..<orbitCount {
            let ratio = CGFloat(index) / CGFloat(max(orbitCount, 1))
            let angle = visualizerPhase * (0.55 + ratio * 0.7) + ratio * .pi * 2
            let orbitRadius = sphereRadius * (1.25 + ratio * 0.48 + smoothedLow * 0.18)
            let dotSize = 4 + smoothedHigh * 6 + ratio * 3
            let point = CGPoint(
                x: center.x + cos(angle) * orbitRadius,
                y: center.y + sin(angle * 1.12) * orbitRadius * 0.82
            )
            let color = blendPalette(palette: palette, ratio: ratio).withAlphaComponent(0.22 + smoothedTransient * 0.4)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: point.x - dotSize / 2, y: point.y - dotSize / 2, width: dotSize, height: dotSize))
        }
    }

    private func drawGlowPath(_ path: NSBezierPath, in context: CGContext, color: NSColor, width: CGFloat) {
        context.saveGState()
        context.setShadow(offset: .zero, blur: width * (1 + visualizerSettings.glow * 2.4), color: color.withAlphaComponent(0.45 + visualizerSettings.glow * 0.25).cgColor)
        color.withAlphaComponent(0.88).setStroke()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
        context.restoreGState()
    }

    private func blendPalette(palette: [NSColor], ratio: CGFloat) -> NSColor {
        if ratio <= 0.5 {
            return palette[0].blended(withFraction: ratio * 2, of: palette[1]) ?? palette[0]
        }
        return palette[1].blended(withFraction: (ratio - 0.5) * 2, of: palette[2]) ?? palette[2]
    }

    private func interpolatedHistory(_ history: [CGFloat], ratio: CGFloat) -> CGFloat {
        guard !history.isEmpty else { return 0 }
        let scaled = ratio * CGFloat(history.count - 1)
        let lowIndex = Int(floor(scaled))
        let highIndex = min(history.count - 1, lowIndex + 1)
        let fraction = scaled - CGFloat(lowIndex)
        return history[lowIndex] + (history[highIndex] - history[lowIndex]) * fraction
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

    private func drawVerticalRail(in context: CGContext, accent: NSColor, glow: NSColor) {
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

    private func drawHorizontalRail(in context: CGContext, accent: NSColor, glow: NSColor) {
        let padding: CGFloat = 44
        let trackWidth = max(bounds.width - padding * 2 - min(bounds.width * 0.08, 64), 120)
        let trackHeight: CGFloat = 2
        let trackX = padding
        let trackY = max(56, bounds.height * 0.18)
        let knobX = trackX + trackWidth * CGFloat(snapshot.secondaryValue) / 100

        context.setFillColor(NSColor.white.withAlphaComponent(0.14).cgColor)
        context.fill(CGRect(x: trackX, y: trackY, width: trackWidth, height: trackHeight))

        context.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        context.fill(CGRect(x: trackX + trackWidth / 2 - 1, y: trackY - 14, width: 2, height: 30))

        let knobSize: CGFloat
        switch snapshot.interaction {
        case .dragging:
            knobSize = 28
        case .hovering:
            knobSize = 26
        case .idle:
            knobSize = 22
        }

        context.setFillColor(glow.withAlphaComponent(0.44).cgColor)
        context.fillEllipse(in: CGRect(x: knobX - knobSize / 2 - 4, y: trackY - knobSize / 2 - 4, width: knobSize + 8, height: knobSize + 8))
        context.setFillColor(accent.cgColor)
        context.fillEllipse(in: CGRect(x: knobX - knobSize / 2, y: trackY - knobSize / 2, width: knobSize, height: knobSize))
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
        let clampedX = min(max(point.x, 0), bounds.width)
        let primaryValue = Int((clampedY / max(controlHeight, 1) * 100).rounded())
        let secondaryValue = Int((clampedX / max(bounds.width, 1) * 100).rounded())
        controller.setLivePoint(primaryValue: primaryValue, secondaryValue: secondaryValue, interaction: interaction)
    }

    private func isPointInsideInteractiveControl(_ point: CGPoint) -> Bool {
        guard let hitView = hitTest(point) else { return false }
        return hitView is NSControl || hitView.superview is NSControl
    }

    private func isPointInsideSettingsPanel(_ point: CGPoint) -> Bool {
        settingsPanelVisible && !settingsPanel.isHidden && settingsPanel.frame.contains(point)
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
