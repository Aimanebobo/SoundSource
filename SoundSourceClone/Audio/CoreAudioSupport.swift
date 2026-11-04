import AudioToolbox
import CoreAudio
import Foundation

// Thin, typed wrappers over the AudioObject property C API.

struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let operation: String

    var errorDescription: String? { "\(operation) failed (\(status.fourCharCode))" }
}

func caCheck(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, operation: operation()) }
}

extension OSStatus {
    /// Core Audio errors are usually four-character codes such as `'!obj'`.
    var fourCharCode: String {
        let value = UInt32(bitPattern: self)
        let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return String(self) }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}

extension AudioObjectPropertyAddress {
    init(_ selector: AudioObjectPropertySelector,
         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
         _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isValid: Bool { self != AudioObjectID.unknown }

    func hasProperty(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(self, &address)
    }

    func isPropertySettable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(self, &address, &settable) == noErr && settable.boolValue
    }

    /// Reads a fixed-size (POD) property value.
    func read<T>(_ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    /// Reads a CFString property (the HAL hands back a +1 reference).
    func readString(_ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Reads a variable-length array of POD values.
    func readArray<T>(_ address: AudioObjectPropertyAddress, of _: T.Type) -> [T] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let capacity = Int(size) / MemoryLayout<T>.stride
        guard capacity > 0 else { return [] }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, buffer) == noErr else { return [] }
        let count = Swift.min(Int(size) / MemoryLayout<T>.stride, capacity)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }

    /// Writes a property value. Pass a CF object (e.g. `uid as CFString`) to write an object reference.
    @discardableResult
    func write<T>(_ address: AudioObjectPropertyAddress, value: T) -> OSStatus {
        var address = address
        var value = value
        return withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(self, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
    }

    /// Total channel count across all streams in a scope (input or output).
    func channelCount(scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

/// Owns one `AudioObjectAddPropertyListenerBlock` registration and removes it on deinit.
final class PropertyListener {
    private let objectID: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private var block: AudioObjectPropertyListenerBlock?

    init(objectID: AudioObjectID,
         address: AudioObjectPropertyAddress,
         queue: DispatchQueue = .main,
         handler: @escaping () -> Void) {
        self.objectID = objectID
        self.address = address
        self.queue = queue
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(objectID, &self.address, queue, block) == noErr {
            self.block = block
        }
    }

    func invalidate() {
        guard let block else { return }
        AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
        self.block = nil
    }

    deinit { invalidate() }
}
