import XCTest
@testable import VolumeCore

final class VolumeCoreTests: XCTestCase {
    func testActiveParameterPrefersShiftOverOption() {
        XCTAssertEqual(AudioControlState.activeParameter(optionPressed: false, shiftPressed: false), .primary)
        XCTAssertEqual(AudioControlState.activeParameter(optionPressed: true, shiftPressed: false), .frequency)
        XCTAssertEqual(AudioControlState.activeParameter(optionPressed: false, shiftPressed: true), .shape)
        XCTAssertEqual(AudioControlState.activeParameter(optionPressed: true, shiftPressed: true), .shape)
    }

    func testBankRouteTargetMapping() {
        let state = AudioControlState()

        XCTAssertEqual(state.target(for: .main, route: .volume), .volume)
        XCTAssertEqual(state.target(for: .main, route: .low), .lowEq)
        XCTAssertEqual(state.target(for: .main, route: .mid), .midEq)
        XCTAssertEqual(state.target(for: .main, route: .high), .highEq)
        XCTAssertEqual(state.target(for: .fx, route: .volume), .filter)
        XCTAssertEqual(state.target(for: .fx, route: .low), .inactive)
        XCTAssertEqual(state.target(for: .fx, route: .mid), .inactive)
        XCTAssertEqual(state.target(for: .fx, route: .high), .echo)
    }

    func testMainBankPrimaryGainMappingRoundTrips() {
        var state = AudioControlState()

        for route in [SurfaceRoute.volume, .low, .mid, .high] {
            state.setNormalizedValue(0, for: .main, route: route, parameter: .primary)
            XCTAssertEqual(state.normalizedValue(for: .main, route: route, parameter: .primary), 0)

            state.setNormalizedValue(50, for: .main, route: route, parameter: .primary)
            XCTAssertEqual(state.normalizedValue(for: .main, route: route, parameter: .primary), 50)

            state.setNormalizedValue(100, for: .main, route: route, parameter: .primary)
            XCTAssertEqual(state.normalizedValue(for: .main, route: route, parameter: .primary), 100)
        }
    }

    func testMainBankFrequencyRangesStayWithinDeclaredBounds() {
        var state = AudioControlState()

        state.setNormalizedValue(0, for: .main, route: .low, parameter: .frequency)
        XCTAssertGreaterThanOrEqual(state.lowFrequencyHz, 40)
        XCTAssertLessThanOrEqual(state.lowFrequencyHz, 240)

        state.setNormalizedValue(100, for: .main, route: .mid, parameter: .frequency)
        XCTAssertGreaterThanOrEqual(state.midFrequencyHz, 250)
        XCTAssertLessThanOrEqual(state.midFrequencyHz, 5_000)

        state.setNormalizedValue(100, for: .main, route: .high, parameter: .frequency)
        XCTAssertGreaterThanOrEqual(state.highFrequencyHz, 4_000)
        XCTAssertLessThanOrEqual(state.highFrequencyHz, 16_000)
    }

    func testFXBankDefaultsAndResetValues() {
        var state = AudioControlState()

        state.setNormalizedValue(100, for: .fx, route: .low, parameter: .primary)
        state.resetValue(for: .fx, route: .low, parameter: .primary)
        XCTAssertEqual(state.displayValue(for: .fx, route: .low, parameter: .primary), "Inactive")

        state.setNormalizedValue(100, for: .fx, route: .mid, parameter: .primary)
        state.resetValue(for: .fx, route: .mid, parameter: .primary)
        XCTAssertEqual(state.displayValue(for: .fx, route: .mid, parameter: .primary), "Inactive")

        state.setNormalizedValue(100, for: .fx, route: .high, parameter: .primary)
        state.resetValue(for: .fx, route: .high, parameter: .primary)
        XCTAssertEqual(state.displayValue(for: .fx, route: .high, parameter: .primary), "0%")

        state.setNormalizedValue(0, for: .fx, route: .high, parameter: .frequency)
        state.resetValue(for: .fx, route: .high, parameter: .frequency)
        XCTAssertTrue(state.displayValue(for: .fx, route: .high, parameter: .frequency).hasSuffix("ms"))
    }

    func testFilterAndMainCoefficientsStayFiniteAcrossExtremes() {
        var state = AudioControlState()
        state.setNormalizedValue(0, for: .main, route: .low, parameter: .primary)
        state.setNormalizedValue(100, for: .main, route: .mid, parameter: .primary)
        state.setNormalizedValue(100, for: .main, route: .high, parameter: .primary)
        state.setNormalizedValue(0, for: .fx, route: .volume, parameter: .primary)
        state.setNormalizedValue(100, for: .fx, route: .volume, parameter: .frequency)
        state.setNormalizedValue(100, for: .fx, route: .volume, parameter: .shape)
        state.setNormalizedValue(100, for: .fx, route: .high, parameter: .primary)
        state.setNormalizedValue(100, for: .fx, route: .high, parameter: .frequency)
        state.setNormalizedValue(100, for: .fx, route: .high, parameter: .shape)

        let configuration = DSPKernel.configuration(for: state, sampleRate: 48_000)
        assertFinite(configuration.low)
        assertFinite(configuration.mid)
        assertFinite(configuration.high)
        assertFinite(configuration.filterLowPass)
        assertFinite(configuration.filterHighPass)
        XCTAssertTrue(configuration.outputGain.isFinite)
        XCTAssertTrue(configuration.limiterCeiling.isFinite)
    }

    func testSoftLimiterNeverExceedsCeiling() {
        let result = DSPKernel.softLimit(2.5, ceiling: DSPKernel.decibelToGain(-3))
        XCTAssertLessThanOrEqual(abs(result.sample), DSPKernel.decibelToGain(-3) + 0.0001)
        XCTAssertTrue(result.clipped)
    }

    func testPointerSecondaryParameterFollowsShiftState() {
        let state = AudioControlState()
        XCTAssertEqual(state.pointerSecondaryParameter(for: .main, route: .low, shiftPressed: false), .frequency)
        XCTAssertEqual(state.pointerSecondaryParameter(for: .main, route: .low, shiftPressed: true), .shape)
        XCTAssertEqual(state.pointerSecondaryParameter(for: .fx, route: .volume, shiftPressed: false), .frequency)
        XCTAssertEqual(state.pointerSecondaryParameter(for: .fx, route: .high, shiftPressed: true), .shape)
    }

    func testDisplayLabelsMatchExpandedControls() {
        let state = AudioControlState()
        XCTAssertEqual(state.descriptor(for: .main, route: .low, parameter: .primary).label, "GAIN")
        XCTAssertEqual(state.descriptor(for: .main, route: .mid, parameter: .shape).label, "Q")
        XCTAssertEqual(state.descriptor(for: .fx, route: .volume, parameter: .primary).label, "FILTER")
        XCTAssertEqual(state.descriptor(for: .fx, route: .volume, parameter: .frequency).label, "RESO")
        XCTAssertEqual(state.descriptor(for: .fx, route: .low, parameter: .primary).label, "EMPTY")
        XCTAssertEqual(state.descriptor(for: .fx, route: .mid, parameter: .primary).label, "EMPTY")
        XCTAssertEqual(state.descriptor(for: .fx, route: .high, parameter: .shape).label, "FDBK")
    }

    private func assertFinite(_ coefficients: BiquadCoefficients, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(coefficients.b0.isFinite, file: file, line: line)
        XCTAssertTrue(coefficients.b1.isFinite, file: file, line: line)
        XCTAssertTrue(coefficients.b2.isFinite, file: file, line: line)
        XCTAssertTrue(coefficients.a1.isFinite, file: file, line: line)
        XCTAssertTrue(coefficients.a2.isFinite, file: file, line: line)
    }
}
