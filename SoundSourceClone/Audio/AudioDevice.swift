import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
    let inputChannels: Int
    let outputChannels: Int
    /// Number of input streams the device itself contributes when used as an aggregate sub-device.
    let inputStreamCount: Int

    var hasOutput: Bool { outputChannels > 0 }
    var hasInput: Bool { inputChannels > 0 }

    var outputSymbol: String { symbol(input: false) }
    var inputSymbol: String { symbol(input: true) }

    private func symbol(input: Bool) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("headphone") || lowered.contains("headset") { return "headphones" }
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return input ? "mic" : "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeVirtual:
            return "waveform"
        case kAudioDeviceTransportTypeAggregate:
            return "square.stack.3d.up"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypePCI:
            return input ? "mic" : "hifispeaker"
        default:
            return input ? "mic" : "speaker.wave.2"
        }
    }
}

extension AudioDevice {
    static func load(_ id: AudioDeviceID) -> AudioDevice? {
        guard let uid = id.readString(.init(kAudioDevicePropertyDeviceUID)) else { return nil }
        if (id.read(.init(kAudioDevicePropertyIsHidden), initial: UInt32(0)) ?? 0) != 0 { return nil }
        let inputStreams = id.readArray(.init(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput),
                                        of: AudioStreamID.self)
        return AudioDevice(
            id: id,
            uid: uid,
            name: id.readString(.init(kAudioObjectPropertyName)) ?? uid,
            transportType: id.read(.init(kAudioDevicePropertyTransportType), initial: UInt32(0)) ?? 0,
            inputChannels: id.channelCount(scope: kAudioObjectPropertyScopeInput),
            outputChannels: id.channelCount(scope: kAudioObjectPropertyScopeOutput),
            inputStreamCount: inputStreams.count
        )
    }

    static func all() -> [AudioDevice] {
        AudioObjectID.system
            .readArray(.init(kAudioHardwarePropertyDevices), of: AudioDeviceID.self)
            .compactMap(load)
    }
}
