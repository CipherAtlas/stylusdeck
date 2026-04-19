import Foundation

public enum SurfaceBank: String, CaseIterable, Codable {
    case main
    case fx
}

public enum SurfaceRoute: String, CaseIterable, Codable {
    case volume
    case low
    case mid
    case high
}

public enum SurfaceParameter: String, CaseIterable, Codable {
    case primary
    case frequency
    case shape
}

public enum SurfaceTarget: String, CaseIterable, Codable {
    case volume
    case lowEq
    case midEq
    case highEq
    case filter
    case inactive
    case echo
}

public struct SurfaceCommand: Codable {
    public let action: String
    public let bank: SurfaceBank?
    public let route: SurfaceRoute?
    public let parameter: SurfaceParameter?
    public let value: Int?
    public let secondaryParameter: SurfaceParameter?
    public let secondaryValue: Int?

    public init(
        action: String,
        bank: SurfaceBank? = nil,
        route: SurfaceRoute? = nil,
        parameter: SurfaceParameter? = nil,
        value: Int? = nil,
        secondaryParameter: SurfaceParameter? = nil,
        secondaryValue: Int? = nil
    ) {
        self.action = action
        self.bank = bank
        self.route = route
        self.parameter = parameter
        self.value = value
        self.secondaryParameter = secondaryParameter
        self.secondaryValue = secondaryValue
    }
}

public struct SurfaceResponse: Codable {
    public let ok: Bool
    public let connected: Bool
    public let backend: String
    public let detail: String
    public let bank: SurfaceBank?
    public let route: SurfaceRoute?
    public let parameter: SurfaceParameter?
    public let value: Int?
    public let displayValue: String?
    public let parameterLabel: String?
    public let secondaryParameter: SurfaceParameter?
    public let secondaryValue: Int?
    public let secondaryDisplayValue: String?
    public let secondaryParameterLabel: String?
    public let outputPeak: Float?
    public let rmsLevel: Float?
    public let lowEnergy: Float?
    public let midEnergy: Float?
    public let highEnergy: Float?
    public let transient: Float?
    public let clipDetected: Bool

    public init(
        ok: Bool,
        connected: Bool,
        backend: String,
        detail: String,
        bank: SurfaceBank? = nil,
        route: SurfaceRoute? = nil,
        parameter: SurfaceParameter? = nil,
        value: Int? = nil,
        displayValue: String? = nil,
        parameterLabel: String? = nil,
        secondaryParameter: SurfaceParameter? = nil,
        secondaryValue: Int? = nil,
        secondaryDisplayValue: String? = nil,
        secondaryParameterLabel: String? = nil,
        outputPeak: Float? = nil,
        rmsLevel: Float? = nil,
        lowEnergy: Float? = nil,
        midEnergy: Float? = nil,
        highEnergy: Float? = nil,
        transient: Float? = nil,
        clipDetected: Bool = false
    ) {
        self.ok = ok
        self.connected = connected
        self.backend = backend
        self.detail = detail
        self.bank = bank
        self.route = route
        self.parameter = parameter
        self.value = value
        self.displayValue = displayValue
        self.parameterLabel = parameterLabel
        self.secondaryParameter = secondaryParameter
        self.secondaryValue = secondaryValue
        self.secondaryDisplayValue = secondaryDisplayValue
        self.secondaryParameterLabel = secondaryParameterLabel
        self.outputPeak = outputPeak
        self.rmsLevel = rmsLevel
        self.lowEnergy = lowEnergy
        self.midEnergy = midEnergy
        self.highEnergy = highEnergy
        self.transient = transient
        self.clipDetected = clipDetected
    }
}

public struct SurfaceControlDescriptor: Equatable {
    public let label: String
    public let defaultNormalizedValue: Int

    public init(label: String, defaultNormalizedValue: Int) {
        self.label = label
        self.defaultNormalizedValue = defaultNormalizedValue
    }
}

public struct AudioControlState: Equatable {
    public var volume: Float
    public var outputTrimDB: Float
    public var limiterCeilingDB: Float
    public var lowGainDB: Float
    public var midGainDB: Float
    public var highGainDB: Float
    public var lowFrequencyHz: Float
    public var midFrequencyHz: Float
    public var highFrequencyHz: Float
    public var lowSlope: Float
    public var midQ: Float
    public var highSlope: Float
    public var filterAmount: Float
    public var filterResonance: Float
    public var filterCharacter: Float
    public var echoWet: Float
    public var echoTimeSeconds: Float
    public var echoFeedback: Float

    public init(
        volume: Float = 0.5,
        outputTrimDB: Float = 0,
        limiterCeilingDB: Float = 0,
        lowGainDB: Float = 0,
        midGainDB: Float = 0,
        highGainDB: Float = 0,
        lowFrequencyHz: Float = 120,
        midFrequencyHz: Float = 1_000,
        highFrequencyHz: Float = 8_000,
        lowSlope: Float = 1.0,
        midQ: Float = 0.85,
        highSlope: Float = 1.0,
        filterAmount: Float = 0,
        filterResonance: Float = 1.1,
        filterCharacter: Float = 0.3,
        echoWet: Float = 0,
        echoTimeSeconds: Float = 0.28,
        echoFeedback: Float = 0.25
    ) {
        self.volume = volume
        self.outputTrimDB = outputTrimDB
        self.limiterCeilingDB = limiterCeilingDB
        self.lowGainDB = lowGainDB
        self.midGainDB = midGainDB
        self.highGainDB = highGainDB
        self.lowFrequencyHz = lowFrequencyHz
        self.midFrequencyHz = midFrequencyHz
        self.highFrequencyHz = highFrequencyHz
        self.lowSlope = lowSlope
        self.midQ = midQ
        self.highSlope = highSlope
        self.filterAmount = filterAmount
        self.filterResonance = filterResonance
        self.filterCharacter = filterCharacter
        self.echoWet = echoWet
        self.echoTimeSeconds = echoTimeSeconds
        self.echoFeedback = echoFeedback
    }

    public static func activeParameter(optionPressed: Bool, shiftPressed: Bool) -> SurfaceParameter {
        if shiftPressed {
            return .shape
        }
        if optionPressed {
            return .frequency
        }
        return .primary
    }

    public func target(for bank: SurfaceBank, route: SurfaceRoute) -> SurfaceTarget {
        switch (bank, route) {
        case (.main, .volume): return .volume
        case (.main, .low): return .lowEq
        case (.main, .mid): return .midEq
        case (.main, .high): return .highEq
        case (.fx, .volume): return .filter
        case (.fx, .low): return .inactive
        case (.fx, .mid): return .inactive
        case (.fx, .high): return .echo
        }
    }

    public func pointerSecondaryParameter(for bank: SurfaceBank, route: SurfaceRoute, shiftPressed: Bool) -> SurfaceParameter {
        if shiftPressed {
            return .shape
        }
        switch target(for: bank, route: route) {
        case .volume, .lowEq, .midEq, .highEq, .filter, .inactive, .echo:
            return .frequency
        }
    }

    public func descriptor(for bank: SurfaceBank, route: SurfaceRoute, parameter: SurfaceParameter) -> SurfaceControlDescriptor {
        switch (target(for: bank, route: route), parameter) {
        case (.volume, .primary), (.lowEq, .primary), (.midEq, .primary), (.highEq, .primary):
            return SurfaceControlDescriptor(label: "GAIN", defaultNormalizedValue: 50)
        case (.volume, .frequency):
            return SurfaceControlDescriptor(label: "TRIM", defaultNormalizedValue: Self.linearToNormalized(0, min: -18, max: 6))
        case (.volume, .shape):
            return SurfaceControlDescriptor(label: "CEILING", defaultNormalizedValue: Self.linearToNormalized(0, min: -6, max: 0))
        case (.lowEq, .frequency):
            return SurfaceControlDescriptor(label: "FREQ", defaultNormalizedValue: Self.logToNormalized(120, min: 40, max: 240))
        case (.midEq, .frequency):
            return SurfaceControlDescriptor(label: "FREQ", defaultNormalizedValue: Self.logToNormalized(1_000, min: 250, max: 5_000))
        case (.highEq, .frequency):
            return SurfaceControlDescriptor(label: "FREQ", defaultNormalizedValue: Self.logToNormalized(8_000, min: 4_000, max: 16_000))
        case (.lowEq, .shape), (.highEq, .shape):
            return SurfaceControlDescriptor(label: "SLOPE", defaultNormalizedValue: Self.linearToNormalized(1.0, min: 0.5, max: 1.2))
        case (.midEq, .shape):
            return SurfaceControlDescriptor(label: "Q", defaultNormalizedValue: Self.linearToNormalized(0.85, min: 0.5, max: 2.0))
        case (.filter, .primary):
            return SurfaceControlDescriptor(label: "FILTER", defaultNormalizedValue: 50)
        case (.filter, .frequency):
            return SurfaceControlDescriptor(label: "RESO", defaultNormalizedValue: Self.linearToNormalized(1.1, min: 0.7, max: 3.0))
        case (.filter, .shape):
            return SurfaceControlDescriptor(label: "CHAR", defaultNormalizedValue: Self.linearToNormalized(0.3, min: 0, max: 1))
        case (.inactive, _):
            return SurfaceControlDescriptor(label: "EMPTY", defaultNormalizedValue: 50)
        case (.echo, .primary):
            return SurfaceControlDescriptor(label: "WET", defaultNormalizedValue: Self.linearToNormalized(0, min: 0, max: 0.7))
        case (.echo, .frequency):
            return SurfaceControlDescriptor(label: "TIME", defaultNormalizedValue: Self.linearToNormalized(0.28, min: 0.06, max: 0.75))
        case (.echo, .shape):
            return SurfaceControlDescriptor(label: "FDBK", defaultNormalizedValue: Self.linearToNormalized(0.25, min: 0, max: 0.82))
        }
    }

    public func normalizedValue(for bank: SurfaceBank, route: SurfaceRoute, parameter: SurfaceParameter) -> Int {
        switch (target(for: bank, route: route), parameter) {
        case (.volume, .primary):
            return Int((volume * 100).rounded())
        case (.volume, .frequency):
            return Self.linearToNormalized(outputTrimDB, min: -18, max: 6)
        case (.volume, .shape):
            return Self.linearToNormalized(limiterCeilingDB, min: -6, max: 0)
        case (.lowEq, .primary):
            return Self.linearToNormalized(lowGainDB, min: -18, max: 18)
        case (.midEq, .primary):
            return Self.linearToNormalized(midGainDB, min: -18, max: 18)
        case (.highEq, .primary):
            return Self.linearToNormalized(highGainDB, min: -18, max: 18)
        case (.lowEq, .frequency):
            return Self.logToNormalized(lowFrequencyHz, min: 40, max: 240)
        case (.midEq, .frequency):
            return Self.logToNormalized(midFrequencyHz, min: 250, max: 5_000)
        case (.highEq, .frequency):
            return Self.logToNormalized(highFrequencyHz, min: 4_000, max: 16_000)
        case (.lowEq, .shape):
            return Self.linearToNormalized(lowSlope, min: 0.5, max: 1.2)
        case (.midEq, .shape):
            return Self.linearToNormalized(midQ, min: 0.5, max: 2.0)
        case (.highEq, .shape):
            return Self.linearToNormalized(highSlope, min: 0.5, max: 1.2)
        case (.filter, .primary):
            return Self.linearToNormalized(filterAmount, min: -1, max: 1)
        case (.filter, .frequency):
            return Self.linearToNormalized(filterResonance, min: 0.7, max: 3.0)
        case (.filter, .shape):
            return Self.linearToNormalized(filterCharacter, min: 0, max: 1)
        case (.inactive, _):
            return 50
        case (.echo, .primary):
            return Self.linearToNormalized(echoWet, min: 0, max: 0.7)
        case (.echo, .frequency):
            return Self.linearToNormalized(echoTimeSeconds, min: 0.06, max: 0.75)
        case (.echo, .shape):
            return Self.linearToNormalized(echoFeedback, min: 0, max: 0.82)
        }
    }

    public mutating func setNormalizedValue(_ normalizedValue: Int, for bank: SurfaceBank, route: SurfaceRoute, parameter: SurfaceParameter) {
        let value = Swift.max(0, Swift.min(100, normalizedValue))
        switch (target(for: bank, route: route), parameter) {
        case (.volume, .primary):
            volume = Float(value) / 100
        case (.volume, .frequency):
            outputTrimDB = Self.normalizedToLinear(value, min: -18, max: 6)
        case (.volume, .shape):
            limiterCeilingDB = Self.normalizedToLinear(value, min: -6, max: 0)
        case (.lowEq, .primary):
            lowGainDB = Self.normalizedToLinear(value, min: -18, max: 18)
        case (.midEq, .primary):
            midGainDB = Self.normalizedToLinear(value, min: -18, max: 18)
        case (.highEq, .primary):
            highGainDB = Self.normalizedToLinear(value, min: -18, max: 18)
        case (.lowEq, .frequency):
            lowFrequencyHz = Self.normalizedToLog(value, min: 40, max: 240)
        case (.midEq, .frequency):
            midFrequencyHz = Self.normalizedToLog(value, min: 250, max: 5_000)
        case (.highEq, .frequency):
            highFrequencyHz = Self.normalizedToLog(value, min: 4_000, max: 16_000)
        case (.lowEq, .shape):
            lowSlope = Self.normalizedToLinear(value, min: 0.5, max: 1.2)
        case (.midEq, .shape):
            midQ = Self.normalizedToLinear(value, min: 0.5, max: 2.0)
        case (.highEq, .shape):
            highSlope = Self.normalizedToLinear(value, min: 0.5, max: 1.2)
        case (.filter, .primary):
            filterAmount = Self.normalizedToLinear(value, min: -1, max: 1)
        case (.filter, .frequency):
            filterResonance = Self.normalizedToLinear(value, min: 0.7, max: 3.0)
        case (.filter, .shape):
            filterCharacter = Self.normalizedToLinear(value, min: 0, max: 1)
        case (.inactive, _):
            break
        case (.echo, .primary):
            echoWet = Self.normalizedToLinear(value, min: 0, max: 0.7)
        case (.echo, .frequency):
            echoTimeSeconds = Self.normalizedToLinear(value, min: 0.06, max: 0.75)
        case (.echo, .shape):
            echoFeedback = Self.normalizedToLinear(value, min: 0, max: 0.82)
        }
    }

    public mutating func resetValue(for bank: SurfaceBank, route: SurfaceRoute, parameter: SurfaceParameter) {
        setNormalizedValue(descriptor(for: bank, route: route, parameter: parameter).defaultNormalizedValue, for: bank, route: route, parameter: parameter)
    }

    public func displayValue(for bank: SurfaceBank, route: SurfaceRoute, parameter: SurfaceParameter) -> String {
        switch (target(for: bank, route: route), parameter) {
        case (.volume, .primary):
            return "\(Int((volume * 100).rounded()))%"
        case (.volume, .frequency):
            return Self.formatDecibels(outputTrimDB)
        case (.volume, .shape):
            return Self.formatDecibels(limiterCeilingDB)
        case (.lowEq, .primary):
            return Self.formatDecibels(lowGainDB)
        case (.midEq, .primary):
            return Self.formatDecibels(midGainDB)
        case (.highEq, .primary):
            return Self.formatDecibels(highGainDB)
        case (.lowEq, .frequency):
            return Self.formatFrequency(lowFrequencyHz)
        case (.midEq, .frequency):
            return Self.formatFrequency(midFrequencyHz)
        case (.highEq, .frequency):
            return Self.formatFrequency(highFrequencyHz)
        case (.lowEq, .shape):
            return Self.formatUnitValue(lowSlope)
        case (.midEq, .shape):
            return Self.formatUnitValue(midQ)
        case (.highEq, .shape):
            return Self.formatUnitValue(highSlope)
        case (.filter, .primary):
            let rounded = filterAmount
            if abs(rounded) < 0.02 {
                return "Center"
            }
            return rounded > 0 ? "LP \(Int(abs(rounded) * 100))%" : "HP \(Int(abs(rounded) * 100))%"
        case (.filter, .frequency):
            return Self.formatUnitValue(filterResonance)
        case (.filter, .shape):
            return "\(Int((filterCharacter * 100).rounded()))%"
        case (.inactive, _):
            return "Inactive"
        case (.echo, .primary):
            return "\(Int((echoWet / 0.7 * 100).rounded()))%"
        case (.echo, .frequency):
            return "\(Int((echoTimeSeconds * 1_000).rounded())) ms"
        case (.echo, .shape):
            return "\(Int((echoFeedback / 0.82 * 100).rounded()))%"
        }
    }

    public func isMomentaryControl(bank: SurfaceBank, route: SurfaceRoute, parameter: SurfaceParameter) -> Bool {
        false
    }

    private static func normalizedToLinear(_ normalized: Int, min minValue: Float, max maxValue: Float) -> Float {
        minValue + (Float(normalized) / 100) * (maxValue - minValue)
    }

    private static func linearToNormalized(_ value: Float, min minValue: Float, max maxValue: Float) -> Int {
        guard maxValue > minValue else { return 0 }
        let ratio = (value - minValue) / (maxValue - minValue)
        return Int((Swift.max(0, Swift.min(1, ratio)) * 100).rounded())
    }

    private static func normalizedToLog(_ normalized: Int, min minValue: Float, max maxValue: Float) -> Float {
        let ratio = Swift.max(0, Swift.min(1, Float(normalized) / 100))
        let minLog = logf(minValue)
        let maxLog = logf(maxValue)
        return expf(minLog + ratio * (maxLog - minLog))
    }

    private static func logToNormalized(_ value: Float, min minValue: Float, max maxValue: Float) -> Int {
        let clamped = Swift.max(minValue, Swift.min(maxValue, value))
        let minLog = logf(minValue)
        let maxLog = logf(maxValue)
        let ratio = (logf(clamped) - minLog) / (maxLog - minLog)
        return Int((Swift.max(0, Swift.min(1, ratio)) * 100).rounded())
    }

    private static func formatDecibels(_ value: Float) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded) < 0.05 {
            return "0.0 dB"
        }
        return String(format: "%+.1f dB", rounded)
    }

    private static func formatFrequency(_ value: Float) -> String {
        if value >= 1_000 {
            let rounded = (value / 100).rounded() / 10
            return String(format: "%.1f kHz", rounded)
        }
        return "\(Int(value.rounded())) Hz"
    }

    private static func formatUnitValue(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}
