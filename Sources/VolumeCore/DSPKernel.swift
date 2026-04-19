import Foundation

public struct BiquadCoefficients: Equatable {
    public var b0: Float
    public var b1: Float
    public var b2: Float
    public var a1: Float
    public var a2: Float

    public init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }
}

public struct DSPConfiguration: Equatable {
    public var low: BiquadCoefficients
    public var mid: BiquadCoefficients
    public var high: BiquadCoefficients
    public var filterLowPass: BiquadCoefficients
    public var filterHighPass: BiquadCoefficients
    public var outputGain: Float
    public var limiterCeiling: Float
    public var filterWet: Float
    public var filterLowPassBlend: Float
    public var filterHighPassBlend: Float
    public var filterCharacter: Float
    public var echoWet: Float
    public var echoFeedback: Float
    public var echoDelaySeconds: Float

    public init(
        low: BiquadCoefficients,
        mid: BiquadCoefficients,
        high: BiquadCoefficients,
        filterLowPass: BiquadCoefficients,
        filterHighPass: BiquadCoefficients,
        outputGain: Float,
        limiterCeiling: Float,
        filterWet: Float,
        filterLowPassBlend: Float,
        filterHighPassBlend: Float,
        filterCharacter: Float,
        echoWet: Float,
        echoFeedback: Float,
        echoDelaySeconds: Float
    ) {
        self.low = low
        self.mid = mid
        self.high = high
        self.filterLowPass = filterLowPass
        self.filterHighPass = filterHighPass
        self.outputGain = outputGain
        self.limiterCeiling = limiterCeiling
        self.filterWet = filterWet
        self.filterLowPassBlend = filterLowPassBlend
        self.filterHighPassBlend = filterHighPassBlend
        self.filterCharacter = filterCharacter
        self.echoWet = echoWet
        self.echoFeedback = echoFeedback
        self.echoDelaySeconds = echoDelaySeconds
    }
}

public enum DSPKernel {
    public static func configuration(for state: AudioControlState, sampleRate: Float) -> DSPConfiguration {
        let filterAmount = max(-1, min(1, state.filterAmount))
        let filterSweep = abs(filterAmount)
        let resonance = max(0.7, min(3.0, state.filterResonance))
        let filterCharacter = max(0, min(1, state.filterCharacter))

        let lowPassCutoff = interpolatedLogValue(amount: filterSweep, minValue: 250, maxValue: 18_000)
        let highPassCutoff = interpolatedLogValue(amount: filterSweep, minValue: 30, maxValue: 8_000)

        return DSPConfiguration(
            low: makeLowShelf(
                frequency: state.lowFrequencyHz,
                gainDB: state.lowGainDB,
                slope: state.lowSlope,
                sampleRate: sampleRate
            ),
            mid: makePeaking(
                frequency: state.midFrequencyHz,
                gainDB: state.midGainDB,
                q: state.midQ,
                sampleRate: sampleRate
            ),
            high: makeHighShelf(
                frequency: state.highFrequencyHz,
                gainDB: state.highGainDB,
                slope: state.highSlope,
                sampleRate: sampleRate
            ),
            filterLowPass: makeLowPass(frequency: lowPassCutoff, q: resonance, sampleRate: sampleRate),
            filterHighPass: makeHighPass(frequency: highPassCutoff, q: resonance, sampleRate: sampleRate),
            outputGain: state.volume * decibelToGain(state.outputTrimDB),
            limiterCeiling: decibelToGain(state.limiterCeilingDB),
            filterWet: filterSweep,
            filterLowPassBlend: filterAmount > 0 ? 1 : 0,
            filterHighPassBlend: filterAmount < 0 ? 1 : 0,
            filterCharacter: filterCharacter,
            echoWet: max(0, min(0.7, state.echoWet)),
            echoFeedback: max(0, min(0.82, state.echoFeedback)),
            echoDelaySeconds: max(0.06, min(0.75, state.echoTimeSeconds))
        )
    }

    public static func decibelToGain(_ value: Float) -> Float {
        powf(10, value / 20)
    }

    public static func softLimit(_ sample: Float, ceiling: Float) -> (sample: Float, clipped: Bool) {
        let safeCeiling = max(0.001, ceiling)
        let limited = tanhf(sample / safeCeiling) * safeCeiling
        return (limited, abs(sample) > safeCeiling)
    }

    public static func applyFilterMacro(
        sample: Float,
        lowPassSample: Float,
        highPassSample: Float,
        wet: Float,
        lowPassBlend: Float,
        highPassBlend: Float,
        character: Float
    ) -> Float {
        let clampedWet = max(0, min(1, wet))
        if clampedWet <= 0.0001 {
            return sample
        }

        let drive = 1 + character * 1.5
        let drivenSample = tanhf(sample * drive) / drive
        let filtered = lowPassSample * lowPassBlend + highPassSample * highPassBlend
        let source = sample * (1 - character * 0.25) + drivenSample * (character * 0.25)
        return source * (1 - clampedWet) + filtered * clampedWet
    }

    public static func blendDryWet(dry: Float, wet: Float, amount: Float) -> Float {
        let clampedAmount = max(0, min(1, amount))
        return dry * (1 - clampedAmount) + wet * clampedAmount
    }

    public static func makePeaking(frequency: Float, gainDB: Float, q: Float, sampleRate: Float) -> BiquadCoefficients {
        let a = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let alpha = sinf(w0) / (2 * max(0.001, q))
        let cosW0 = cosf(w0)
        return normalize(
            b0: 1 + alpha * a,
            b1: -2 * cosW0,
            b2: 1 - alpha * a,
            a0: 1 + alpha / a,
            a1: -2 * cosW0,
            a2: 1 - alpha / a
        )
    }

    public static func makeLowShelf(frequency: Float, gainDB: Float, slope: Float, sampleRate: Float) -> BiquadCoefficients {
        let a = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let cosW0 = cosf(w0)
        let sinW0 = sinf(w0)
        let alpha = shelfAlpha(a: a, slope: slope, sinW0: sinW0)
        let beta = 2 * sqrtf(a) * alpha

        return normalize(
            b0: a * ((a + 1) - (a - 1) * cosW0 + beta),
            b1: 2 * a * ((a - 1) - (a + 1) * cosW0),
            b2: a * ((a + 1) - (a - 1) * cosW0 - beta),
            a0: (a + 1) + (a - 1) * cosW0 + beta,
            a1: -2 * ((a - 1) + (a + 1) * cosW0),
            a2: (a + 1) + (a - 1) * cosW0 - beta
        )
    }

    public static func makeHighShelf(frequency: Float, gainDB: Float, slope: Float, sampleRate: Float) -> BiquadCoefficients {
        let a = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let cosW0 = cosf(w0)
        let sinW0 = sinf(w0)
        let alpha = shelfAlpha(a: a, slope: slope, sinW0: sinW0)
        let beta = 2 * sqrtf(a) * alpha

        return normalize(
            b0: a * ((a + 1) + (a - 1) * cosW0 + beta),
            b1: -2 * a * ((a - 1) + (a + 1) * cosW0),
            b2: a * ((a + 1) + (a - 1) * cosW0 - beta),
            a0: (a + 1) - (a - 1) * cosW0 + beta,
            a1: 2 * ((a - 1) - (a + 1) * cosW0),
            a2: (a + 1) - (a - 1) * cosW0 - beta
        )
    }

    public static func makeLowPass(frequency: Float, q: Float, sampleRate: Float) -> BiquadCoefficients {
        let w0 = 2 * Float.pi * frequency / sampleRate
        let cosW0 = cosf(w0)
        let alpha = sinf(w0) / (2 * max(0.001, q))
        return normalize(
            b0: (1 - cosW0) / 2,
            b1: 1 - cosW0,
            b2: (1 - cosW0) / 2,
            a0: 1 + alpha,
            a1: -2 * cosW0,
            a2: 1 - alpha
        )
    }

    public static func makeHighPass(frequency: Float, q: Float, sampleRate: Float) -> BiquadCoefficients {
        let w0 = 2 * Float.pi * frequency / sampleRate
        let cosW0 = cosf(w0)
        let alpha = sinf(w0) / (2 * max(0.001, q))
        return normalize(
            b0: (1 + cosW0) / 2,
            b1: -(1 + cosW0),
            b2: (1 + cosW0) / 2,
            a0: 1 + alpha,
            a1: -2 * cosW0,
            a2: 1 - alpha
        )
    }

    private static func interpolatedLogValue(amount: Float, minValue: Float, maxValue: Float) -> Float {
        let ratio = max(0, min(1, amount))
        let minLog = logf(minValue)
        let maxLog = logf(maxValue)
        return expf(maxLog + (minLog - maxLog) * ratio)
    }

    private static func shelfAlpha(a: Float, slope: Float, sinW0: Float) -> Float {
        let safeSlope = max(0.01, slope)
        let term = (a + (1 / a)) * ((1 / safeSlope) - 1) + 2
        return sinW0 / 2 * sqrtf(max(term, 0))
    }

    private static func normalize(b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float) -> BiquadCoefficients {
        BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}
