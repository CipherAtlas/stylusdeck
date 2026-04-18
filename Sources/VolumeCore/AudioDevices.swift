import CoreAudio
import Foundation

public enum AudioDeviceError: Error {
    case osStatus(OSStatus)
    case deviceNotFound(String)
    case missingProperty(String)
}

public enum AudioDevices {
    public static func allDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )

        guard sizeStatus == noErr else {
            throw AudioDeviceError.osStatus(sizeStatus)
        }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        let getStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        guard getStatus == noErr else {
            throw AudioDeviceError.osStatus(getStatus)
        }

        return deviceIDs
    }

    public static func deviceName(for deviceID: AudioDeviceID) throws -> String {
        try readStringProperty(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    public static func deviceUID(for deviceID: AudioDeviceID) throws -> String {
        try readStringProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    public static func findDevice(named name: String) throws -> AudioDeviceID {
        for deviceID in try allDeviceIDs() {
            if try deviceName(for: deviceID) == name {
                return deviceID
            }
        }

        throw AudioDeviceError.deviceNotFound(name)
    }

    public static func defaultOutputDevice() throws -> AudioDeviceID {
        try readDeviceIDProperty(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    public static func defaultSystemOutputDevice() throws -> AudioDeviceID {
        try readDeviceIDProperty(selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    public static func setDefaultOutputDevice(_ deviceID: AudioDeviceID) throws {
        try writeDeviceIDProperty(selector: kAudioHardwarePropertyDefaultOutputDevice, deviceID: deviceID)
    }

    public static func setDefaultSystemOutputDevice(_ deviceID: AudioDeviceID) throws {
        try writeDeviceIDProperty(selector: kAudioHardwarePropertyDefaultSystemOutputDevice, deviceID: deviceID)
    }

    public static func firstUsableOutputDevice(excluding excludedID: AudioDeviceID? = nil) throws -> AudioDeviceID? {
        for deviceID in try allDeviceIDs() {
            if let excludedID, deviceID == excludedID {
                continue
            }

            if try outputChannelCount(for: deviceID) > 0 {
                return deviceID
            }
        }

        return nil
    }

    public static func outputChannelCount(for deviceID: AudioDeviceID) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
        guard sizeStatus == noErr else {
            throw AudioDeviceError.osStatus(sizeStatus)
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferListPointer)
        guard status == noErr else {
            throw AudioDeviceError.osStatus(status)
        }

        let bufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    public static func nominalSampleRate(for deviceID: AudioDeviceID) throws -> Double {
        var sampleRate = Float64.zero
        var propertySize = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &sampleRate
        )

        guard status == noErr else {
            throw AudioDeviceError.osStatus(status)
        }

        return sampleRate
    }

    public static func setNominalSampleRate(_ sampleRate: Double, for deviceID: AudioDeviceID) throws {
        var mutableSampleRate = Float64(sampleRate)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &mutableSampleRate
        )

        guard status == noErr else {
            throw AudioDeviceError.osStatus(status)
        }
    }

    public static func processObjectID(for pid: pid_t) throws -> AudioObjectID {
        var targetPID = pid
        var processID = AudioObjectID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &targetPID,
            &propertySize,
            &processID
        )

        guard status == noErr else {
            throw AudioDeviceError.osStatus(status)
        }

        guard processID != AudioObjectID(kAudioObjectUnknown) else {
            throw AudioDeviceError.missingProperty("processObjectID(pid=\(pid))")
        }

        return processID
    }

    private static func readDeviceIDProperty(selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr else {
            throw AudioDeviceError.osStatus(status)
        }

        return deviceID
    }

    private static func writeDeviceIDProperty(selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) throws {
        var mutableDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )

        guard status == noErr else {
            throw AudioDeviceError.osStatus(status)
        }
    }

    private static func readStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else {
            throw AudioDeviceError.missingProperty("selector=\(selector)")
        }

        var unmanaged: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &propertySize,
            &unmanaged
        )

        guard status == noErr, let unmanaged else {
            throw AudioDeviceError.osStatus(status)
        }

        return unmanaged.takeRetainedValue() as String
    }
}
