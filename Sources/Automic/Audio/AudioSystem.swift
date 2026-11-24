import AudioToolbox
import AutomicKit
import CoreAudio
import Foundation

/// A failed CoreAudio call, with what was being done and the status as a four-character code.
struct CoreAudioError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        "\(operation) failed with OSStatus \(status) (\(Self.fourCharacterCode(status)))"
    }

    static func fourCharacterCode(_ status: OSStatus) -> String {
        let bytes = withUnsafeBytes(of: UInt32(bitPattern: status).bigEndian) { Array($0) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return "\(status)" }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// A device CoreAudio lists, with the scopes it can be the default for.
struct SystemDevice: Equatable {
    var id: AudioObjectID
    var device: AudioDevice
    var scopes: Set<AudioScope>
}

/// Thin wrapper over the CoreAudio HAL: devices, the default devices, and change notifications.
enum AudioSystem {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    // MARK: Devices

    /// Every visible device that can be the default input or output. A device that fails to
    /// report a property (often one that is disconnecting) is left out and logged.
    static func devices() throws -> [SystemDevice] {
        let ids: [AudioObjectID] = try readArray(system, address(kAudioHardwarePropertyDevices), "list devices")
        return ids.compactMap { id in
            do {
                return try describe(id)
            } catch {
                Log.audio.error("Skipping device \(id): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private static func describe(_ id: AudioObjectID) throws -> SystemDevice? {
        let hidden: UInt32 = (try? read(id, address(kAudioDevicePropertyIsHidden), "read hidden flag")) ?? 0
        guard hidden == 0 else { return nil }
        var scopes = Set<AudioScope>()
        for scope in AudioScope.allCases where try canBeDefault(id, scope) {
            scopes.insert(scope)
        }
        guard !scopes.isEmpty else { return nil }
        let uid = try readString(id, address(kAudioDevicePropertyDeviceUID), "read device UID")
        let name = try readString(id, address(kAudioObjectPropertyName), "read device name")
        let transportType: UInt32 = (try? read(id, address(kAudioDevicePropertyTransportType), "read transport type")) ?? 0
        return SystemDevice(id: id, device: AudioDevice(uid: uid, name: name, transport: transport(transportType)), scopes: scopes)
    }

    /// Has streams in that direction and does not refuse to be the default for it.
    private static func canBeDefault(_ id: AudioObjectID, _ scope: AudioScope) throws -> Bool {
        let streams: [AudioStreamID] = try readArray(id, address(kAudioDevicePropertyStreams, scope: scope.coreAudio), "list streams")
        guard !streams.isEmpty else { return false }
        let allowed: UInt32 = (try? read(id, address(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: scope.coreAudio), "read can-be-default")) ?? 1
        return allowed != 0
    }

    private static func transport(_ type: UInt32) -> AudioTransport {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: .display
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: .continuity
        case kAudioDeviceTransportTypeVirtual: .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: .aggregate
        default: .other
        }
    }

    // MARK: Defaults

    static func defaultDevice(_ scope: AudioScope) throws -> AudioObjectID {
        try read(system, address(scope.defaultSelector), "read default \(scope.rawValue) device")
    }

    static func setDefaultDevice(_ scope: AudioScope, to id: AudioObjectID) throws {
        var address = address(scope.defaultSelector)
        var value = id
        let status = AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
        guard status == noErr else { throw CoreAudioError(operation: "set default \(scope.rawValue) device", status: status) }
    }

    // MARK: Volume

    /// The device's main volume for `scope`, 0...1, or nil when it has no volume control
    /// (HDMI and DisplayPort displays, many virtual devices).
    static func volume(_ id: AudioObjectID, _ scope: AudioScope) -> Float? {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope.coreAudio)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue else { return nil }
        do {
            let value: Float32 = try read(id, address, "read \(scope.rawValue) volume")
            return value
        } catch {
            Log.audio.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func setVolume(_ id: AudioObjectID, _ scope: AudioScope, to volume: Float) throws {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope.coreAudio)
        var value = Float32(min(max(volume, 0), 1))
        let status = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        guard status == noErr else { throw CoreAudioError(operation: "set \(scope.rawValue) volume", status: status) }
    }

    /// Calls `handler` on the main queue when the device's volume for `scope` changes, for
    /// instance from the volume keys, until the returned observation is cancelled.
    static func observeVolume(_ id: AudioObjectID, _ scope: AudioScope, _ handler: @escaping @MainActor () -> Void) -> PropertyObservation? {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope.coreAudio)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        let block = listener(handler)
        let status = AudioObjectAddPropertyListenerBlock(id, &address, .main, block)
        guard status == noErr else {
            Log.audio.error("\(CoreAudioError(operation: "observe \(scope.rawValue) volume", status: status).localizedDescription, privacy: .public)")
            return nil
        }
        return PropertyObservation(object: id, address: address, block: block)
    }

    // MARK: Notifications

    /// Calls `handler` on the main queue whenever the device list changes. Lives as long as the app.
    static func observeDevices(_ handler: @escaping @MainActor () -> Void) throws {
        try observe(address(kAudioHardwarePropertyDevices), "observe devices", handler)
    }

    /// Calls `handler` on the main queue whenever the default device of `scope` changes.
    static func observeDefault(_ scope: AudioScope, _ handler: @escaping @MainActor () -> Void) throws {
        try observe(address(scope.defaultSelector), "observe default \(scope.rawValue) device", handler)
    }

    private static func observe(_ address: AudioObjectPropertyAddress, _ operation: String, _ handler: @escaping @MainActor () -> Void) throws {
        var address = address
        let status = AudioObjectAddPropertyListenerBlock(system, &address, .main, listener(handler))
        guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
    }

    /// Built outside the main actor: CoreAudio calls the block on the queue it was given, `.main`.
    private nonisolated static func listener(_ handler: @escaping @MainActor () -> Void) -> AudioObjectPropertyListenerBlock {
        { _, _ in MainActor.assumeIsolated { handler() } }
    }

    // MARK: Property access

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ operation: String) throws -> T {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { value.deallocate() }
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, value)
        guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
        return value.load(as: T.self)
    }

    private static func readArray<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ operation: String) throws -> [T] {
        var address = address
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size)
        guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }
        status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer)
        guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
        let typed = buffer.bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: typed, count: Int(size) / MemoryLayout<T>.stride))
    }

    /// CoreAudio hands out a retained CFString the caller releases.
    private static func readString(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ operation: String) throws -> String {
        var address = address
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
        guard let string = value?.takeRetainedValue() else {
            throw CoreAudioError(operation: operation, status: kAudioHardwareUnspecifiedError)
        }
        return string as String
    }
}

/// A listener on one device property; `cancel()` removes it. A device that is gone has
/// dropped its listeners already, so a failure to remove is only logged.
final class PropertyObservation {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock
    private var isCancelled = false

    init(object: AudioObjectID, address: AudioObjectPropertyAddress, block: @escaping AudioObjectPropertyListenerBlock) {
        self.object = object
        self.address = address
        self.block = block
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        let status = AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        if status != noErr {
            Log.audio.debug("Removing a volume listener: \(CoreAudioError(operation: "remove listener", status: status).localizedDescription, privacy: .public)")
        }
    }
}

private extension AudioScope {
    var coreAudio: AudioObjectPropertyScope {
        switch self {
        case .output: kAudioObjectPropertyScopeOutput
        case .input: kAudioObjectPropertyScopeInput
        }
    }

    var defaultSelector: AudioObjectPropertySelector {
        switch self {
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        case .input: kAudioHardwarePropertyDefaultInputDevice
        }
    }
}
