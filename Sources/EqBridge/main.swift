import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import VolumeCore

private struct Command: Decodable {
    let action: String
    let band: String?
    let value: Int?
}

struct Response: Encodable {
    let ok: Bool
    let connected: Bool
    let backend: String
    let detail: String
    let band: String?
    let value: Int?
}

private struct BiquadCoefficients {
    var b0: Float
    var b1: Float
    var b2: Float
    var a1: Float
    var a2: Float
}

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
    private var bandValues: [String: Int] = ["low": 50, "mid": 50, "high": 50]
    private var lowCoefficients = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    private var midCoefficients = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    private var highCoefficients = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    private var channelStates = [ChannelState(), ChannelState()]
    private var masterVolume: Float = 1
    private var started = false
    private var detail = "Idle"
    private var captureCallbacks: UInt64 = 0
    private var outputCallbacks: UInt64 = 0
    private var lastInputPeak: Float = 0
    private var lastOutputPeak: Float = 0
    private var captureBuffer: UnsafeMutablePointer<Float>

    init() {
        captureBuffer = .allocate(capacity: Int(maxCaptureFrames * channels))
        captureBuffer.initialize(repeating: 0, count: Int(maxCaptureFrames * channels))
        recalculateCoefficients()
    }

    deinit {
        captureBuffer.deinitialize(count: Int(maxCaptureFrames * channels))
        captureBuffer.deallocate()
    }

    func status(for band: String?) -> Response {
        do {
            try ensureStarted()
            lock.lock()
            let captureCallbacks = self.captureCallbacks
            let outputCallbacks = self.outputCallbacks
            let inputPeak = self.lastInputPeak
            let outputPeak = self.lastOutputPeak
            lock.unlock()
            let stats = String(
                format: "cap=%llu out=%llu in=%.4f out=%.4f",
                captureCallbacks,
                outputCallbacks,
                inputPeak,
                outputPeak
            )
            return Response(
                ok: true,
                connected: true,
                backend: "native-eq",
                detail: "\(detail) · \(stats)",
                band: band,
                value: band.flatMap { bandValues[$0] }
            )
        } catch {
            return Response(
                ok: false,
                connected: false,
                backend: "native-eq",
                detail: error.localizedDescription,
                band: band,
                value: band.flatMap { bandValues[$0] }
            )
        }
    }

    func setBand(_ band: String, value: Int) -> Response {
        do {
            try ensureStarted()
            let clamped = max(0, min(100, value))
            lock.lock()
            bandValues[band] = clamped
            recalculateCoefficients()
            lock.unlock()
            return Response(ok: true, connected: true, backend: "native-eq", detail: detail, band: band, value: clamped)
        } catch {
            return Response(ok: false, connected: false, backend: "native-eq", detail: error.localizedDescription, band: band, value: value)
        }
    }

    func getOutputVolume() -> Response {
        do {
            try ensureStarted()
            lock.lock()
            let value = Int((masterVolume * 100).rounded())
            lock.unlock()
            return Response(ok: true, connected: true, backend: "native-eq", detail: detail, band: nil, value: value)
        } catch {
            return Response(ok: false, connected: false, backend: "native-eq", detail: error.localizedDescription, band: nil, value: nil)
        }
    }

    func setOutputVolume(_ value: Int) -> Response {
        do {
            try ensureStarted()
            let clamped = max(0, min(100, value))
            lock.lock()
            masterVolume = Float(clamped) / 100
            lock.unlock()
            return Response(ok: true, connected: true, backend: "native-eq", detail: detail, band: nil, value: clamped)
        } catch {
            return Response(ok: false, connected: false, backend: "native-eq", detail: error.localizedDescription, band: nil, value: value)
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
        let gain = masterVolume
        lock.unlock()

        var inputPeak: Float = 0
        var outputPeak: Float = 0
        for frame in 0..<Int(frameCount) {
            let leftIndex = frame * 2
            let rightIndex = leftIndex + 1

            var left = captureBuffer[leftIndex]
            inputPeak = max(inputPeak, abs(left))
            left = channelStates[0].low.process(left, coefficients: low)
            left = channelStates[0].mid.process(left, coefficients: mid)
            left = channelStates[0].high.process(left, coefficients: high)
            captureBuffer[leftIndex] = left * gain
            outputPeak = max(outputPeak, abs(captureBuffer[leftIndex]))

            var right = captureBuffer[rightIndex]
            inputPeak = max(inputPeak, abs(right))
            right = channelStates[1].low.process(right, coefficients: low)
            right = channelStates[1].mid.process(right, coefficients: mid)
            right = channelStates[1].high.process(right, coefficients: high)
            captureBuffer[rightIndex] = right * gain
            outputPeak = max(outputPeak, abs(captureBuffer[rightIndex]))
        }

        monitorRingBuffer.write(captureBuffer, count: sampleCount)
        blackHoleRingBuffer.write(captureBuffer, count: sampleCount)

        lock.lock()
        captureCallbacks &+= 1
        lastInputPeak = inputPeak
        lastOutputPeak = outputPeak
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
        let rate = Float(sampleRate)
        lowCoefficients = makeLowShelf(frequency: 120, gainDB: mappedGain(bandValues["low"] ?? 50), sampleRate: rate)
        midCoefficients = makePeaking(frequency: 1_000, gainDB: mappedGain(bandValues["mid"] ?? 50), q: 0.85, sampleRate: rate)
        highCoefficients = makeHighShelf(frequency: 8_000, gainDB: mappedGain(bandValues["high"] ?? 50), sampleRate: rate)
    }

    private func mappedGain(_ value: Int) -> Float {
        (Float(value - 50) / 50) * 18
    }

    private func makePeaking(frequency: Float, gainDB: Float, q: Float, sampleRate: Float) -> BiquadCoefficients {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)
        return normalize(
            b0: 1 + alpha * a,
            b1: -2 * cosW0,
            b2: 1 - alpha * a,
            a0: 1 + alpha / a,
            a1: -2 * cosW0,
            a2: 1 - alpha / a
        )
    }

    private func makeLowShelf(frequency: Float, gainDB: Float, sampleRate: Float) -> BiquadCoefficients {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let sqrtA = sqrt(a)
        let alpha = sinW0 / 2 * sqrt(2)
        return normalize(
            b0: a * ((a + 1) - (a - 1) * cosW0 + 2 * sqrtA * alpha),
            b1: 2 * a * ((a - 1) - (a + 1) * cosW0),
            b2: a * ((a + 1) - (a - 1) * cosW0 - 2 * sqrtA * alpha),
            a0: (a + 1) + (a - 1) * cosW0 + 2 * sqrtA * alpha,
            a1: -2 * ((a - 1) + (a + 1) * cosW0),
            a2: (a + 1) + (a - 1) * cosW0 - 2 * sqrtA * alpha
        )
    }

    private func makeHighShelf(frequency: Float, gainDB: Float, sampleRate: Float) -> BiquadCoefficients {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let sqrtA = sqrt(a)
        let alpha = sinW0 / 2 * sqrt(2)
        return normalize(
            b0: a * ((a + 1) + (a - 1) * cosW0 + 2 * sqrtA * alpha),
            b1: -2 * a * ((a - 1) + (a + 1) * cosW0),
            b2: a * ((a + 1) + (a - 1) * cosW0 - 2 * sqrtA * alpha),
            a0: (a + 1) - (a - 1) * cosW0 + 2 * sqrtA * alpha,
            a1: 2 * ((a - 1) - (a + 1) * cosW0),
            a2: (a + 1) - (a - 1) * cosW0 - 2 * sqrtA * alpha
        )
    }

    private func normalize(b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float) -> BiquadCoefficients {
        BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
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

nonisolated(unsafe) private let processor = EqProcessor()
private let decoder = JSONDecoder()
private let encoder = JSONEncoder()

private func writeResponse(_ response: Response) {
    guard let data = try? encoder.encode(response) else {
        return
    }

    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

private func installSignalHandlers() {
    signal(SIGINT) { _ in
        processor.restoreRoute()
        exit(0)
    }
    signal(SIGTERM) { _ in
        processor.restoreRoute()
        exit(0)
    }
}

installSignalHandlers()

while let line = readLine() {
    guard let data = line.data(using: .utf8) else {
        writeResponse(Response(ok: false, connected: false, backend: "native-eq", detail: "Invalid UTF-8 input", band: nil, value: nil))
        continue
    }

    do {
        let command = try decoder.decode(Command.self, from: data)
        switch command.action {
        case "status":
            writeResponse(processor.status(for: command.band))
        case "setBand":
            guard let band = command.band, let value = command.value else {
                writeResponse(Response(ok: false, connected: false, backend: "native-eq", detail: "Missing band or value", band: command.band, value: command.value))
                continue
            }
            writeResponse(processor.setBand(band, value: value))
        case "getVolume":
            writeResponse(processor.getOutputVolume())
        case "setVolume":
            guard let value = command.value else {
                writeResponse(Response(ok: false, connected: false, backend: "native-eq", detail: "Missing volume value", band: nil, value: nil))
                continue
            }
            writeResponse(processor.setOutputVolume(value))
        default:
            writeResponse(Response(ok: false, connected: false, backend: "native-eq", detail: "Unknown action: \(command.action)", band: command.band, value: command.value))
        }
    } catch {
        writeResponse(Response(ok: false, connected: false, backend: "native-eq", detail: error.localizedDescription, band: nil, value: nil))
    }
}

processor.restoreRoute()
