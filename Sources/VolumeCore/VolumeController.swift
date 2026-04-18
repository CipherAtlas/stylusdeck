import CoreAudio

public final class VolumeController {
    private var cachedDeviceID: AudioDeviceID?
    private var lastMuteState: Bool?

    public init() {}

    public func currentVolume() -> Float32 {
        do {
            let deviceID = try currentOutputDevice()
            return try currentVolume(for: deviceID)
        } catch {
            cachedDeviceID = nil
        }

        return 0.5
    }

    public func currentVolume(for deviceID: AudioDeviceID) throws -> Float32 {
        do {
            if let volume = try readMasterVolume(from: deviceID) {
                return volume
            }

            if let volume = try readChannelVolume(from: deviceID) {
                return volume
            }
        } catch {
            throw error
        }

        return 0.5
    }

    public func setVolume(_ scalar: Float32) {
        let clamped = max(0, min(1, scalar))

        do {
            let deviceID = try currentOutputDevice()
            try setVolume(clamped, for: deviceID)
        } catch {
            cachedDeviceID = nil
        }
    }

    public func setVolume(_ scalar: Float32, for deviceID: AudioDeviceID) throws {
        let clamped = max(0, min(1, scalar))

        do {
            if try setMasterVolume(clamped, on: deviceID) {
                updateMuteState(deviceID: deviceID, volume: clamped)
                return
            }

            if try setChannelVolume(clamped, on: deviceID) {
                updateMuteState(deviceID: deviceID, volume: clamped)
                return
            }
        } catch {
            throw error
        }
    }

    private func currentOutputDevice() throws -> AudioDeviceID {
        if let cachedDeviceID {
            return cachedDeviceID
        }

        let deviceID = try AudioDevices.defaultOutputDevice()
        cachedDeviceID = deviceID
        return deviceID
    }

    private func readMasterVolume(from deviceID: AudioDeviceID) throws -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var volume = Float32.zero
        var propertySize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &volume
        )

        guard status == noErr else {
            throw AudioDeviceError.osStatus(status)
        }

        return volume
    }

    private func readChannelVolume(from deviceID: AudioDeviceID) throws -> Float32? {
        let channels: [UInt32] = [1, 2]
        var volumes: [Float32] = []

        for channel in channels {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )

            guard AudioObjectHasProperty(deviceID, &address) else {
                continue
            }

            var volume = Float32.zero
            var propertySize = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &propertySize,
                &volume
            )

            guard status == noErr else {
                throw AudioDeviceError.osStatus(status)
            }

            volumes.append(volume)
        }

        guard !volumes.isEmpty else {
            return nil
        }

        return volumes.reduce(0, +) / Float32(volumes.count)
    }

    private func setMasterVolume(_ volume: Float32, on deviceID: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        var mutableVolume = volume
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &mutableVolume
        )

        if status == noErr {
            return true
        }

        throw AudioDeviceError.osStatus(status)
    }

    private func setChannelVolume(_ volume: Float32, on deviceID: AudioDeviceID) throws -> Bool {
        let channels: [UInt32] = [1, 2]
        var changedAnyChannel = false

        for channel in channels {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )

            guard AudioObjectHasProperty(deviceID, &address) else {
                continue
            }

            var mutableVolume = volume
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float32>.size),
                &mutableVolume
            )

            guard status == noErr else {
                throw AudioDeviceError.osStatus(status)
            }

            changedAnyChannel = true
        }

        return changedAnyChannel
    }

    private func updateMuteState(deviceID: AudioDeviceID, volume: Float32) {
        let shouldMute = volume <= 0.001
        if lastMuteState == shouldMute {
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return
        }

        var mute: UInt32 = shouldMute ? 1 : 0
        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &mute
        )
        lastMuteState = shouldMute
    }
}
