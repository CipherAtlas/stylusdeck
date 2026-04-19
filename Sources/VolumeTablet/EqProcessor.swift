import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import VolumeCore

typealias EqBridgeResponse = SurfaceResponse

private struct BiquadState {
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0

    mutating func process(_ sample: Float, coefficients: BiquadCoefficients) -> Float {
        let output = coefficients.b0 * sample
            + coefficients.b1 * x1
            + coefficients.b2 * x2
            - coefficients.a1 * y1
            - coefficients.a2 * y2

        x2 = x1
        x1 = sample
        y2 = y1
        y1 = output
        return output
    }
}

private struct ChannelState {
    var low = BiquadState()
    var mid = BiquadState()
    var high = BiquadState()
    var filterLowPass = BiquadState()
    var filterHighPass = BiquadState()
}

private final class SampleRingBuffer {
    private let lock = NSLock()
    private var storage: [Float]
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0

    init(capacity: Int) {
        storage = Array(repeating: 0, count: capacity)
    }

    func write(_ samples: UnsafePointer<Float>, count sampleCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        let writable = min(sampleCount, storage.count)
        if writable == 0 {
            return
        }

        if count + writable > storage.count {
            let overflow = count + writable - storage.count
            readIndex = (readIndex + overflow) % storage.count
            count -= overflow
        }

        for index in 0..<writable {
            storage[writeIndex] = samples[index]
            writeIndex = (writeIndex + 1) % storage.count
        }
        count += writable
    }

    func read(into output: UnsafeMutablePointer<Float>, count sampleCount: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let readable = min(sampleCount, count)
        for index in 0..<readable {
            output[index] = storage[readIndex]
            readIndex = (readIndex + 1) % storage.count
        }
        count -= readable
        return readable
    }

    func clear() {
        lock.lock()
        readIndex = 0
        writeIndex = 0
        count = 0
        lock.unlock()
    }
}

final class EqProcessor {
    private let lock = NSLock()
    private let outputFramesPerBuffer: UInt32 = 1024
    private let maxCaptureFrames: UInt32 = 4096
    private let aggregateReadyDelayUS: useconds_t = 80_000
    private let monitorRingBuffer = SampleRingBuffer(capacity: 48_000 * 8)
    private let blackHoleRingBuffer = SampleRingBuffer(capacity: 48_000 * 8)
    private let echoBufferCapacity = 48_000 * 4

    private var inputUnit: AudioUnit?
    private var monitorOutputQueue: AudioQueueRef?
    private var monitorOutputBuffers: [AudioQueueBufferRef] = []
    private var blackHoleOutputQueue: AudioQueueRef?
    private var blackHoleOutputBuffers: [AudioQueueBufferRef] = []
    private var tapObjectID: AudioObjectID?
    private var tapUID: String?
    private var captureDeviceID: AudioDeviceID?
    private var blackHoleDeviceID: AudioDeviceID?
    private var monitorOutputDeviceID: AudioDeviceID?
    private var originalDefaultOutputDeviceID: AudioDeviceID?
    private var originalSystemOutputDeviceID: AudioDeviceID?
    private var redirectedDefaultOutput = false
    private var redirectedSystemOutput = false
    private var sampleRate: Double = 48_000
    private let channels: UInt32 = 2
    private var controlState = AudioControlState()
    private var lowCoefficients = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    private var midCoefficients = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    private var highCoefficients = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    private var filterLowPassCoefficients = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    private var filterHighPassCoefficients = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    private var channelStates = [ChannelState(), ChannelState()]
    private var outputGain: Float = 1
    private var limiterCeiling: Float = 1
    private var filterWet: Float = 0
    private var filterLowPassBlend: Float = 0
    private var filterHighPassBlend: Float = 0
    private var filterCharacter: Float = 0
    private var echoWet: Float = 0
    private var echoFeedback: Float = 0
    private var echoDelaySamplesTarget: Int = 1
    private var echoDelaySamplesCurrent: Int = 1
    private var echoLeftBuffer: [Float]
    private var echoRightBuffer: [Float]
    private var echoWriteIndex = 0
    private var started = false
    private var detail = "Idle"
    private var captureCallbacks: UInt64 = 0
    private var outputCallbacks: UInt64 = 0
    private var lastInputPeak: Float = 0
    private var lastOutputPeak: Float = 0
    private var lastRMSLevel: Float = 0
    private var lastLowEnergy: Float = 0
    private var lastMidEnergy: Float = 0
    private var lastHighEnergy: Float = 0
    private var lastTransient: Float = 0
    private var lastClipDetected = false
    private var clipHoldCallbacks = 0
    private var analyzerLowState: Float = 0
    private var analyzerHighState: Float = 0
    private var analyzerPreviousSample: Float = 0
    private var analyzerPreviousPeak: Float = 0
    private var captureBuffer: UnsafeMutablePointer<Float>

    init() {
        captureBuffer = .allocate(capacity: Int(maxCaptureFrames * channels))
        captureBuffer.initialize(repeating: 0, count: Int(maxCaptureFrames * channels))
        echoLeftBuffer = Array(repeating: 0, count: echoBufferCapacity)
        echoRightBuffer = Array(repeating: 0, count: echoBufferCapacity)
        recalculateCoefficients()
    }

    deinit {
        captureBuffer.deinitialize(count: Int(maxCaptureFrames * channels))
        captureBuffer.deallocate()
    }

    func status(
        for bank: SurfaceBank,
        route: SurfaceRoute,
        parameter: SurfaceParameter,
        secondaryParameter: SurfaceParameter? = nil
    ) -> EqBridgeResponse {
        do {
            try ensureStarted()
            return makeResponse(bank: bank, route: route, parameter: parameter, secondaryParameter: secondaryParameter)
        } catch {
            return makeErrorResponse(error, bank: bank, route: route, parameter: parameter, secondaryParameter: secondaryParameter)
        }
    }

    func setValue(
        _ value: Int,
        for bank: SurfaceBank,
        route: SurfaceRoute,
        parameter: SurfaceParameter,
        secondaryParameter: SurfaceParameter? = nil
    ) -> EqBridgeResponse {
        do {
            try ensureStarted()
            let clamped = max(0, min(100, value))
            lock.lock()
            controlState.setNormalizedValue(clamped, for: bank, route: route, parameter: parameter)
            recalculateCoefficients()
            lock.unlock()
            return makeResponse(bank: bank, route: route, parameter: parameter, secondaryParameter: secondaryParameter)
        } catch {
            return makeErrorResponse(error, bank: bank, route: route, parameter: parameter, secondaryParameter: secondaryParameter)
        }
    }

    func setGesture(
        primaryValue: Int,
        secondaryValue: Int,
        for bank: SurfaceBank,
        route: SurfaceRoute,
        secondaryParameter: SurfaceParameter
    ) -> EqBridgeResponse {
        do {
            try ensureStarted()
            let clampedPrimary = max(0, min(100, primaryValue))
            let clampedSecondary = max(0, min(100, secondaryValue))
            lock.lock()
            controlState.setNormalizedValue(clampedPrimary, for: bank, route: route, parameter: .primary)
            controlState.setNormalizedValue(clampedSecondary, for: bank, route: route, parameter: secondaryParameter)
            recalculateCoefficients()
            lock.unlock()
            return makeResponse(bank: bank, route: route, parameter: .primary, secondaryParameter: secondaryParameter)
        } catch {
            return makeErrorResponse(error, bank: bank, route: route, parameter: .primary, secondaryParameter: secondaryParameter)
        }
    }

    func restoreRoute() {
        if redirectedDefaultOutput, let originalDefaultOutputDeviceID {
            try? AudioDevices.setDefaultOutputDevice(originalDefaultOutputDeviceID)
        }
        if redirectedSystemOutput, let originalSystemOutputDeviceID {
            try? AudioDevices.setDefaultSystemOutputDevice(originalSystemOutputDeviceID)
        }
        redirectedDefaultOutput = false
        redirectedSystemOutput = false
        originalDefaultOutputDeviceID = nil
        originalSystemOutputDeviceID = nil

        if let inputUnit {
            AudioOutputUnitStop(inputUnit)
            AudioUnitUninitialize(inputUnit)
            AudioComponentInstanceDispose(inputUnit)
            self.inputUnit = nil
        }

        if let monitorOutputQueue {
            AudioQueueStop(monitorOutputQueue, true)
            AudioQueueDispose(monitorOutputQueue, true)
            self.monitorOutputQueue = nil
            self.monitorOutputBuffers.removeAll()
        }

        if let blackHoleOutputQueue {
            AudioQueueStop(blackHoleOutputQueue, true)
            AudioQueueDispose(blackHoleOutputQueue, true)
            self.blackHoleOutputQueue = nil
            self.blackHoleOutputBuffers.removeAll()
        }

        if let captureDeviceID {
            _ = AudioHardwareDestroyAggregateDevice(AudioObjectID(captureDeviceID))
            self.captureDeviceID = nil
        }

        if let tapObjectID {
            if #available(macOS 14.2, *) {
                _ = AudioHardwareDestroyProcessTap(tapObjectID)
            }
            self.tapObjectID = nil
            self.tapUID = nil
        }

        monitorRingBuffer.clear()
        blackHoleRingBuffer.clear()
        echoLeftBuffer = Array(repeating: 0, count: echoBufferCapacity)
        echoRightBuffer = Array(repeating: 0, count: echoBufferCapacity)
        echoWriteIndex = 0
        started = false
        detail = "Idle"
    }

    private func ensureStarted() throws {
        if started {
            return
        }

        do {
            try resolveDevices()
            try createProcessTap()
            try createCaptureDevice()
            try configureInputUnit()
            try configureOutputQueues()
            try startIO()
            started = true
        } catch {
            restoreRoute()
            throw error
        }
    }

    private func resolveDevices() throws {
        let blackHoleName = ProcessInfo.processInfo.environment["EQ_INPUT_DEVICE_NAME"] ?? "BlackHole 2ch"
        let blackHoleID = try AudioDevices.findDevice(named: blackHoleName)
        let currentDefaultOutput = try AudioDevices.defaultOutputDevice()
        let currentSystemOutput = try AudioDevices.defaultSystemOutputDevice()

        let monitorDeviceID: AudioDeviceID
        if let forcedName = ProcessInfo.processInfo.environment["EQ_OUTPUT_DEVICE_NAME"] {
            monitorDeviceID = try AudioDevices.findDevice(named: forcedName)
        } else if let headphones = try? AudioDevices.findDevice(named: "External Headphones") {
            monitorDeviceID = headphones
        } else if currentDefaultOutput != blackHoleID {
            monitorDeviceID = currentDefaultOutput
        } else if currentSystemOutput != blackHoleID {
            monitorDeviceID = currentSystemOutput
        } else if let speakers = try? AudioDevices.findDevice(named: "MacBook Air Speakers") {
            monitorDeviceID = speakers
        } else if let fallback = try AudioDevices.firstUsableOutputDevice(excluding: blackHoleID) {
            monitorDeviceID = fallback
        } else {
            throw AudioDeviceError.deviceNotFound("No monitor output device outside BlackHole")
        }

        guard monitorDeviceID != blackHoleID else {
            throw AudioDeviceError.deviceNotFound("Wet monitor output cannot be BlackHole 2ch")
        }

        let outputName = try AudioDevices.deviceName(for: monitorDeviceID)
        let monitorRate = try AudioDevices.nominalSampleRate(for: monitorDeviceID)
        try? AudioDevices.setNominalSampleRate(monitorRate, for: blackHoleID)

        redirectedDefaultOutput = false
        redirectedSystemOutput = false
        originalDefaultOutputDeviceID = nil
        originalSystemOutputDeviceID = nil

        if currentDefaultOutput == blackHoleID {
            try? AudioDevices.setDefaultOutputDevice(monitorDeviceID)
            originalDefaultOutputDeviceID = currentDefaultOutput
            redirectedDefaultOutput = true
        }

        if currentSystemOutput == blackHoleID {
            try? AudioDevices.setDefaultSystemOutputDevice(monitorDeviceID)
            originalSystemOutputDeviceID = currentSystemOutput
            redirectedSystemOutput = true
        }

        blackHoleDeviceID = blackHoleID
        monitorOutputDeviceID = monitorDeviceID
        sampleRate = monitorRate
        if redirectedDefaultOutput || redirectedSystemOutput {
            detail = "System tap -> \(outputName) + \(blackHoleName) · monitor override active"
        } else {
            detail = "System tap -> \(outputName) + \(blackHoleName)"
        }
        channelStates = [ChannelState(), ChannelState()]
        monitorRingBuffer.clear()
        blackHoleRingBuffer.clear()
        lock.lock()
        captureCallbacks = 0
        outputCallbacks = 0
        lastInputPeak = 0
        lastOutputPeak = 0
        lastRMSLevel = 0
        lastLowEnergy = 0
        lastMidEnergy = 0
        lastHighEnergy = 0
        lastTransient = 0
        lastClipDetected = false
        clipHoldCallbacks = 0
        analyzerLowState = 0
        analyzerHighState = 0
        analyzerPreviousSample = 0
        analyzerPreviousPeak = 0
        lock.unlock()
        recalculateCoefficients()
    }

    private func createProcessTap() throws {
        guard #available(macOS 14.2, *) else {
            throw AudioDeviceError.missingProperty("Process taps require macOS 14.2 or newer")
        }

        let processObjectID = try AudioDevices.processObjectID(for: getpid())
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [processObjectID])
        tapDescription.name = "StylusDeck Tap"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .muted

        var tapObjectID = AudioObjectID(0)
        try check(AudioHardwareCreateProcessTap(tapDescription, &tapObjectID))
        self.tapObjectID = tapObjectID
        tapUID = tapDescription.uuid.uuidString
    }

    private func createCaptureDevice() throws {
        guard let tapUID else {
            throw AudioDeviceError.missingProperty("tapUID")
        }

        let captureUID = "com.openai.StylusDeck.capture.\(UUID().uuidString)"
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "StylusDeck Capture",
            kAudioAggregateDeviceUIDKey: captureUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: 1,
                ],
            ],
        ]

        var deviceID = AudioObjectID(0)
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &deviceID))
        usleep(aggregateReadyDelayUS)
        captureDeviceID = AudioDeviceID(deviceID)
        if let captureDeviceID, let captureRate = try? AudioDevices.nominalSampleRate(for: captureDeviceID) {
            sampleRate = captureRate
        }
    }

    private func configureInputUnit() throws {
        guard let captureDeviceID else {
            throw AudioDeviceError.deviceNotFound("Capture aggregate device")
        }

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioDeviceError.deviceNotFound("HAL input component")
        }

        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &unit))
        guard let unit else {
            throw AudioDeviceError.deviceNotFound("HAL input unit")
        }

        var enableInput: UInt32 = 1
        var disableOutput: UInt32 = 0
        var deviceID = captureDeviceID
        var maxFrames = maxCaptureFrames
        var streamFormat = makeStreamFormat()
        var callback = AURenderCallbackStruct(
            inputProc: inputCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableInput, UInt32(MemoryLayout<UInt32>.size)))
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disableOutput, UInt32(MemoryLayout<UInt32>.size)))
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)))
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, UInt32(MemoryLayout<UInt32>.size)))

        inputUnit = unit
    }

    private func configureOutputQueues() throws {
        guard let monitorOutputDeviceID, let blackHoleDeviceID else {
            throw AudioDeviceError.missingProperty("Output devices are not resolved")
        }

        monitorOutputQueue = try makeOutputQueue(for: monitorOutputDeviceID, callback: monitorOutputCallback, storeIn: &monitorOutputBuffers)
        blackHoleOutputQueue = try makeOutputQueue(for: blackHoleDeviceID, callback: blackHoleOutputCallback, storeIn: &blackHoleOutputBuffers)
    }

    private func makeOutputQueue(
        for deviceID: AudioDeviceID,
        callback: AudioQueueOutputCallback,
        storeIn buffers: inout [AudioQueueBufferRef]
    ) throws -> AudioQueueRef {
        var queue: AudioQueueRef?
        var streamFormat = makeStreamFormat()
        try check(AudioQueueNewOutput(
            &streamFormat,
            callback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            nil,
            nil,
            0,
            &queue
        ))

        guard let queue else {
            throw AudioDeviceError.deviceNotFound("AudioQueue output")
        }

        var deviceUID = try AudioDevices.deviceUID(for: deviceID) as CFString
        let deviceStatus = withUnsafePointer(to: &deviceUID) { pointer in
            AudioQueueSetProperty(
                queue,
                kAudioQueueProperty_CurrentDevice,
                pointer,
                UInt32(MemoryLayout<CFString>.size)
            )
        }
        try check(deviceStatus)

        let bytesPerBuffer = UInt32(Int(outputFramesPerBuffer) * Int(streamFormat.mBytesPerFrame))
        for _ in 0..<3 {
            var bufferRef: AudioQueueBufferRef?
            try check(AudioQueueAllocateBuffer(queue, bytesPerBuffer, &bufferRef))
            if let bufferRef {
                fillSilence(bufferRef, byteCount: bytesPerBuffer)
                try check(AudioQueueEnqueueBuffer(queue, bufferRef, 0, nil))
                buffers.append(bufferRef)
            }
        }

        return queue
    }

    private func startIO() throws {
        guard let inputUnit, let monitorOutputQueue, let blackHoleOutputQueue else {
            throw AudioDeviceError.missingProperty("Audio units are not configured")
        }

        try check(AudioUnitInitialize(inputUnit))
        try check(AudioQueueStart(monitorOutputQueue, nil))
        try check(AudioQueueStart(blackHoleOutputQueue, nil))
        try check(AudioOutputUnitStart(inputUnit))
    }

    private func makeStreamFormat() -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    func handleInputCallback(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard let inputUnit else {
            return noErr
        }

        let sampleCount = Int(frameCount * channels)
        let byteCount = sampleCount * MemoryLayout<Float>.size
        let audioBuffer = AudioBuffer(
            mNumberChannels: channels,
            mDataByteSize: UInt32(byteCount),
            mData: UnsafeMutableRawPointer(captureBuffer)
        )
        var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)

        let status = AudioUnitRender(inputUnit, flags, timeStamp, 1, frameCount, &bufferList)
        guard status == noErr else {
            return status
        }

        lock.lock()
        let low = lowCoefficients
        let mid = midCoefficients
        let high = highCoefficients
        let filterLowPass = filterLowPassCoefficients
        let filterHighPass = filterHighPassCoefficients
        let gain = outputGain
        let ceiling = limiterCeiling
        let filterWet = self.filterWet
        let filterLowPassBlend = self.filterLowPassBlend
        let filterHighPassBlend = self.filterHighPassBlend
        let filterCharacter = self.filterCharacter
        let echoWet = self.echoWet
        let echoFeedback = self.echoFeedback
        let echoDelayTarget = self.echoDelaySamplesTarget
        lock.unlock()

        var inputPeak: Float = 0
        var outputPeak: Float = 0
        var sumSquares: Float = 0
        var lowSum: Float = 0
        var midSum: Float = 0
        var highSum: Float = 0
        var clipDetected = false
        for frame in 0..<Int(frameCount) {
            let leftIndex = frame * 2
            let rightIndex = leftIndex + 1

            var left = captureBuffer[leftIndex]
            inputPeak = max(inputPeak, abs(left))
            left = channelStates[0].low.process(left, coefficients: low)
            left = channelStates[0].mid.process(left, coefficients: mid)
            left = channelStates[0].high.process(left, coefficients: high)
            let leftLowPass = channelStates[0].filterLowPass.process(left, coefficients: filterLowPass)
            let leftHighPass = channelStates[0].filterHighPass.process(left, coefficients: filterHighPass)
            left = DSPKernel.applyFilterMacro(
                sample: left,
                lowPassSample: leftLowPass,
                highPassSample: leftHighPass,
                wet: filterWet,
                lowPassBlend: filterLowPassBlend,
                highPassBlend: filterHighPassBlend,
                character: filterCharacter
            )
            left *= gain
            left = processEchoSample(
                dry: left,
                delayedBuffer: &echoLeftBuffer,
                wet: echoWet,
                feedback: echoFeedback,
                targetDelaySamples: echoDelayTarget,
                frameOffset: frame
            )
            let leftLimited = DSPKernel.softLimit(left, ceiling: ceiling)
            captureBuffer[leftIndex] = leftLimited.sample
            clipDetected = clipDetected || leftLimited.clipped
            outputPeak = max(outputPeak, abs(captureBuffer[leftIndex]))

            var right = captureBuffer[rightIndex]
            inputPeak = max(inputPeak, abs(right))
            right = channelStates[1].low.process(right, coefficients: low)
            right = channelStates[1].mid.process(right, coefficients: mid)
            right = channelStates[1].high.process(right, coefficients: high)
            let rightLowPass = channelStates[1].filterLowPass.process(right, coefficients: filterLowPass)
            let rightHighPass = channelStates[1].filterHighPass.process(right, coefficients: filterHighPass)
            right = DSPKernel.applyFilterMacro(
                sample: right,
                lowPassSample: rightLowPass,
                highPassSample: rightHighPass,
                wet: filterWet,
                lowPassBlend: filterLowPassBlend,
                highPassBlend: filterHighPassBlend,
                character: filterCharacter
            )
            right *= gain
            right = processEchoSample(
                dry: right,
                delayedBuffer: &echoRightBuffer,
                wet: echoWet,
                feedback: echoFeedback,
                targetDelaySamples: echoDelayTarget,
                frameOffset: frame
            )
            let rightLimited = DSPKernel.softLimit(right, ceiling: ceiling)
            captureBuffer[rightIndex] = rightLimited.sample
            clipDetected = clipDetected || rightLimited.clipped
            outputPeak = max(outputPeak, abs(captureBuffer[rightIndex]))

            let mono = (captureBuffer[leftIndex] + captureBuffer[rightIndex]) * 0.5
            analyzerLowState += 0.025 * (mono - analyzerLowState)
            let highInput = mono - analyzerPreviousSample
            analyzerHighState += 0.18 * (highInput - analyzerHighState)
            analyzerPreviousSample = mono

            let lowBand = analyzerLowState
            let highBand = analyzerHighState
            let midBand = mono - lowBand - highBand
            sumSquares += mono * mono
            lowSum += abs(lowBand)
            midSum += abs(midBand)
            highSum += abs(highBand)
        }
        echoWriteIndex = (echoWriteIndex + Int(frameCount)) % echoBufferCapacity

        monitorRingBuffer.write(captureBuffer, count: sampleCount)
        blackHoleRingBuffer.write(captureBuffer, count: sampleCount)

        lock.lock()
        captureCallbacks &+= 1
        lastInputPeak = inputPeak
        lastOutputPeak = outputPeak
        let frameCountFloat = max(Float(frameCount), 1)
        let rms = sqrtf(sumSquares / frameCountFloat)
        lastRMSLevel = min(1, rms * 2.4)
        lastLowEnergy = min(1, lowSum / frameCountFloat * 3.2)
        lastMidEnergy = min(1, midSum / frameCountFloat * 4.2)
        lastHighEnergy = min(1, highSum / frameCountFloat * 6.0)
        lastTransient = min(1, max(0, outputPeak - analyzerPreviousPeak) * 4.5)
        analyzerPreviousPeak = outputPeak
        if clipDetected {
            lastClipDetected = true
            clipHoldCallbacks = 24
        } else if clipHoldCallbacks > 0 {
            clipHoldCallbacks -= 1
            lastClipDetected = true
        } else {
            lastClipDetected = false
        }
        lock.unlock()
        return noErr
    }

    private func fillSilence(_ buffer: AudioQueueBufferRef, byteCount: UInt32) {
        let sampleCount = Int(byteCount) / MemoryLayout<Float>.size
        let outputPointer = buffer.pointee.mAudioData.assumingMemoryBound(to: Float.self)
        outputPointer.initialize(repeating: 0, count: sampleCount)
        buffer.pointee.mAudioDataByteSize = byteCount
    }

    private func fillOutputBuffer(from ringBuffer: SampleRingBuffer, buffer: AudioQueueBufferRef, byteCount: UInt32) {
        let sampleCount = Int(byteCount) / MemoryLayout<Float>.size
        let outputPointer = buffer.pointee.mAudioData.assumingMemoryBound(to: Float.self)

        let read = ringBuffer.read(into: outputPointer, count: sampleCount)
        if read < sampleCount {
            outputPointer.advanced(by: read).initialize(repeating: 0, count: sampleCount - read)
        }

        buffer.pointee.mAudioDataByteSize = byteCount
        lock.lock()
        outputCallbacks &+= 1
        lock.unlock()
    }

    func fillMonitorOutputBuffer(_ buffer: AudioQueueBufferRef, byteCount: UInt32) {
        fillOutputBuffer(from: monitorRingBuffer, buffer: buffer, byteCount: byteCount)
    }

    func fillBlackHoleOutputBuffer(_ buffer: AudioQueueBufferRef, byteCount: UInt32) {
        fillOutputBuffer(from: blackHoleRingBuffer, buffer: buffer, byteCount: byteCount)
    }

    private func recalculateCoefficients() {
        let config = DSPKernel.configuration(for: controlState, sampleRate: Float(sampleRate))
        lowCoefficients = config.low
        midCoefficients = config.mid
        highCoefficients = config.high
        filterLowPassCoefficients = config.filterLowPass
        filterHighPassCoefficients = config.filterHighPass
        outputGain = config.outputGain
        limiterCeiling = config.limiterCeiling
        filterWet = config.filterWet
        filterLowPassBlend = config.filterLowPassBlend
        filterHighPassBlend = config.filterHighPassBlend
        filterCharacter = config.filterCharacter
        echoWet = config.echoWet
        echoFeedback = config.echoFeedback
        echoDelaySamplesTarget = max(1, min(echoBufferCapacity - 1, Int((config.echoDelaySeconds * Float(sampleRate)).rounded())))
    }

    private func makeResponse(
        bank: SurfaceBank,
        route: SurfaceRoute,
        parameter: SurfaceParameter,
        secondaryParameter: SurfaceParameter? = nil
    ) -> EqBridgeResponse {
        lock.lock()
        let captureCallbacks = self.captureCallbacks
        let outputCallbacks = self.outputCallbacks
        let inputPeak = self.lastInputPeak
        let outputPeak = self.lastOutputPeak
        let rmsLevel = self.lastRMSLevel
        let lowEnergy = self.lastLowEnergy
        let midEnergy = self.lastMidEnergy
        let highEnergy = self.lastHighEnergy
        let transient = self.lastTransient
        let clipDetected = self.lastClipDetected
        let displayValue = controlState.displayValue(for: bank, route: route, parameter: parameter)
        let value = controlState.normalizedValue(for: bank, route: route, parameter: parameter)
        let parameterLabel = controlState.descriptor(for: bank, route: route, parameter: parameter).label
        let secondaryValue = secondaryParameter.map { controlState.normalizedValue(for: bank, route: route, parameter: $0) }
        let secondaryDisplayValue = secondaryParameter.map { controlState.displayValue(for: bank, route: route, parameter: $0) }
        let secondaryParameterLabel = secondaryParameter.map { controlState.descriptor(for: bank, route: route, parameter: $0).label }
        lock.unlock()
        let stats = String(
            format: "cap=%llu out=%llu in=%.4f out=%.4f",
            captureCallbacks,
            outputCallbacks,
            inputPeak,
            outputPeak
        )
        return EqBridgeResponse(
            ok: true,
            connected: true,
            backend: "native-eq",
            detail: "\(detail) · \(stats)",
            bank: bank,
            route: route,
            parameter: parameter,
            value: value,
            displayValue: displayValue,
            parameterLabel: parameterLabel,
            secondaryParameter: secondaryParameter,
            secondaryValue: secondaryValue,
            secondaryDisplayValue: secondaryDisplayValue,
            secondaryParameterLabel: secondaryParameterLabel,
            outputPeak: outputPeak,
            rmsLevel: rmsLevel,
            lowEnergy: lowEnergy,
            midEnergy: midEnergy,
            highEnergy: highEnergy,
            transient: transient,
            clipDetected: clipDetected
        )
    }

    private func makeErrorResponse(
        _ error: Error,
        bank: SurfaceBank,
        route: SurfaceRoute,
        parameter: SurfaceParameter,
        secondaryParameter: SurfaceParameter? = nil
    ) -> EqBridgeResponse {
        EqBridgeResponse(
            ok: false,
            connected: false,
            backend: "native-eq",
            detail: error.localizedDescription,
            bank: bank,
            route: route,
            parameter: parameter,
            value: controlState.normalizedValue(for: bank, route: route, parameter: parameter),
            displayValue: controlState.displayValue(for: bank, route: route, parameter: parameter),
            parameterLabel: controlState.descriptor(for: bank, route: route, parameter: parameter).label,
            secondaryParameter: secondaryParameter,
            secondaryValue: secondaryParameter.map { controlState.normalizedValue(for: bank, route: route, parameter: $0) },
            secondaryDisplayValue: secondaryParameter.map { controlState.displayValue(for: bank, route: route, parameter: $0) },
            secondaryParameterLabel: secondaryParameter.map { controlState.descriptor(for: bank, route: route, parameter: $0).label },
            outputPeak: lastOutputPeak,
            rmsLevel: lastRMSLevel,
            lowEnergy: lastLowEnergy,
            midEnergy: lastMidEnergy,
            highEnergy: lastHighEnergy,
            transient: lastTransient,
            clipDetected: lastClipDetected
        )
    }

    private func processEchoSample(
        dry: Float,
        delayedBuffer: inout [Float],
        wet: Float,
        feedback: Float,
        targetDelaySamples: Int,
        frameOffset: Int
    ) -> Float {
        if echoDelaySamplesCurrent != targetDelaySamples {
            let delta = targetDelaySamples - echoDelaySamplesCurrent
            let stepMagnitude = min(abs(delta), 8)
            echoDelaySamplesCurrent += delta > 0 ? stepMagnitude : -stepMagnitude
        }

        let writeIndex = (echoWriteIndex + frameOffset) % echoBufferCapacity
        let readIndex = (writeIndex - echoDelaySamplesCurrent + echoBufferCapacity) % echoBufferCapacity
        let delayed = delayedBuffer[readIndex]
        let send: Float = wet > 0.001 ? 1 : 0
        delayedBuffer[writeIndex] = dry * send + delayed * feedback
        return dry + delayed * wet
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw AudioDeviceError.osStatus(status)
        }
    }
}

nonisolated(unsafe) private let inputCallback: AURenderCallback = { refCon, ioActionFlags, inTimeStamp, _, inNumberFrames, _ in
    let processor = Unmanaged<EqProcessor>.fromOpaque(refCon).takeUnretainedValue()
    return processor.handleInputCallback(flags: ioActionFlags, timeStamp: inTimeStamp, frameCount: inNumberFrames)
}

nonisolated(unsafe) private let monitorOutputCallback: AudioQueueOutputCallback = { refCon, queue, buffer in
    let processor = Unmanaged<EqProcessor>.fromOpaque(refCon!).takeUnretainedValue()
    let byteCount = buffer.pointee.mAudioDataBytesCapacity
    processor.fillMonitorOutputBuffer(buffer, byteCount: byteCount)
    AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
}

nonisolated(unsafe) private let blackHoleOutputCallback: AudioQueueOutputCallback = { refCon, queue, buffer in
    let processor = Unmanaged<EqProcessor>.fromOpaque(refCon!).takeUnretainedValue()
    let byteCount = buffer.pointee.mAudioDataBytesCapacity
    processor.fillBlackHoleOutputBuffer(buffer, byteCount: byteCount)
    AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
}
