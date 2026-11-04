import AppKit
import AudioToolbox
import CoreAudio
import Observation

/// System-level audio state: device lists, default devices, hardware volume/mute, alert volume.
@MainActor @Observable
final class AudioDeviceManager {
    enum Change { case deviceList, defaultOutput, defaultInput, systemOutput }

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultOutputID = AudioObjectID.unknown
    private(set) var defaultInputID = AudioObjectID.unknown
    private(set) var systemOutputID = AudioObjectID.unknown

    private(set) var outputVolume: Float = 0
    private(set) var outputMuted = false
    private(set) var outputVolumeAvailable = false
    private(set) var outputBalance: Float = 0
    private(set) var outputBalanceAvailable = false
    private(set) var outputSampleRate: Double = 0
    private(set) var outputSampleRates: [Double] = []

    private(set) var inputVolume: Float = 0
    private(set) var inputMuted = false
    private(set) var inputVolumeAvailable = false

    private(set) var alertVolume: Float = 1

    @ObservationIgnored var onChange: ((Change) -> Void)?
    let isPreview: Bool
    @ObservationIgnored private var systemListeners: [PropertyListener] = []
    @ObservationIgnored private var outputListeners: [PropertyListener] = []
    @ObservationIgnored private var inputListeners: [PropertyListener] = []
    @ObservationIgnored private var listenedOutputID = AudioObjectID.unknown
    @ObservationIgnored private var listenedInputID = AudioObjectID.unknown
    @ObservationIgnored private var inputVolumeBeforeSoftMute: Float?
    @ObservationIgnored private var alertWorkItem: DispatchWorkItem?

    var outputDevices: [AudioDevice] { devices.filter(\.hasOutput) }
    var inputDevices: [AudioDevice] { devices.filter(\.hasInput) }
    var defaultOutput: AudioDevice? { devices.first { $0.id == defaultOutputID } }
    var defaultInput: AudioDevice? { devices.first { $0.id == defaultInputID } }
    var systemOutput: AudioDevice? { devices.first { $0.id == systemOutputID } }

    func device(uid: String) -> AudioDevice? { devices.first { $0.uid == uid } }
    func device(id: AudioObjectID) -> AudioDevice? { devices.first { $0.id == id } }

    init(preview: Bool = false) {
        isPreview = preview
        if preview { loadPreviewState() }
    }

    func start() {
        guard !isPreview else { return }
        let selectors = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
        ]
        systemListeners = selectors.map { selector in
            PropertyListener(objectID: .system, address: .init(selector)) { [weak self] in
                self?.systemPropertyChanged(selector)
            }
        }
        reloadDevices()
        reloadDefaults()
        alertVolume = AlertVolume.read() ?? alertVolume
    }

    /// Re-reads values that have no reliable change notification (alert volume) or may have drifted.
    func refresh() {
        guard !isPreview else { return }
        refreshOutputState()
        refreshInputState()
        if let volume = AlertVolume.read() { alertVolume = volume }
    }

    // MARK: Default devices

    func setDefaultOutput(_ device: AudioDevice) {
        setSystemDevice(kAudioHardwarePropertyDefaultOutputDevice, to: device)
    }

    func setDefaultInput(_ device: AudioDevice) {
        setSystemDevice(kAudioHardwarePropertyDefaultInputDevice, to: device)
    }

    func setSoundEffectsOutput(_ device: AudioDevice) {
        setSystemDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, to: device)
    }

    private func setSystemDevice(_ selector: AudioObjectPropertySelector, to device: AudioDevice) {
        if isPreview {
            switch selector {
            case kAudioHardwarePropertyDefaultOutputDevice: defaultOutputID = device.id
            case kAudioHardwarePropertyDefaultInputDevice: defaultInputID = device.id
            default: systemOutputID = device.id
            }
            return
        }
        let status = AudioObjectID.system.write(.init(selector), value: device.id)
        if status != noErr { NSLog("SoundSourceClone: could not select \(device.name): \(status.fourCharCode)") }
        reloadDefaults()
    }

    // MARK: Output

    func setOutputVolume(_ value: Float) {
        let volume = min(max(value, 0), 1)
        outputVolume = volume
        guard !isPreview else { return }
        Self.writeVolume(defaultOutputID, scope: kAudioObjectPropertyScopeOutput, value: volume)
        if outputMuted, volume > 0 { setOutputMuted(false) }
    }

    func toggleOutputMute() { setOutputMuted(!outputMuted) }

    func setOutputMuted(_ muted: Bool) {
        outputMuted = muted
        guard !isPreview else { return }
        let address = AudioObjectPropertyAddress(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        defaultOutputID.write(address, value: UInt32(muted ? 1 : 0))
    }

    /// -1 (left) … 0 (centre) … +1 (right).
    func setOutputBalance(_ value: Float) {
        let balance = min(max(value, -1), 1)
        outputBalance = balance
        guard !isPreview else { return }
        let address = AudioObjectPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainBalance,
                                                 kAudioObjectPropertyScopeOutput)
        defaultOutputID.write(address, value: Float32((balance + 1) / 2))
    }

    func setOutputSampleRate(_ rate: Double) {
        outputSampleRate = rate
        guard !isPreview else { return }
        defaultOutputID.write(.init(kAudioDevicePropertyNominalSampleRate), value: Float64(rate))
    }

    // MARK: Input

    func setInputVolume(_ value: Float) {
        let volume = min(max(value, 0), 1)
        inputVolume = volume
        guard !isPreview else { return }
        Self.writeVolume(defaultInputID, scope: kAudioObjectPropertyScopeInput, value: volume)
        if inputMuted, volume > 0 { setInputMuted(false) }
    }

    func toggleInputMute() { setInputMuted(!inputMuted) }

    func setInputMuted(_ muted: Bool) {
        inputMuted = muted
        guard !isPreview else { return }
        let address = AudioObjectPropertyAddress(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
        if defaultInputID.isPropertySettable(address) {
            defaultInputID.write(address, value: UInt32(muted ? 1 : 0))
        } else if muted {
            // Many USB/Bluetooth mics have no mute control: fall back to zero gain and remember the level.
            inputVolumeBeforeSoftMute = inputVolume
            Self.writeVolume(defaultInputID, scope: kAudioObjectPropertyScopeInput, value: 0)
        } else {
            let restored = inputVolumeBeforeSoftMute ?? 0.5
            inputVolumeBeforeSoftMute = nil
            inputVolume = restored
            Self.writeVolume(defaultInputID, scope: kAudioObjectPropertyScopeInput, value: restored)
        }
    }

    // MARK: Alert (sound effects) volume

    func setAlertVolume(_ value: Float) {
        alertVolume = min(max(value, 0), 1)
        guard !isPreview else { return }
        // AppleScript round-trips are slow; coalesce slider drags.
        alertWorkItem?.cancel()
        let volume = alertVolume
        let item = DispatchWorkItem { AlertVolume.write(volume) }
        alertWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    // MARK: Change handling

    private func systemPropertyChanged(_ selector: AudioObjectPropertySelector) {
        switch selector {
        case kAudioHardwarePropertyDevices:
            // Creating/destroying our own private aggregates also fires this; only real changes count.
            guard reloadDevices() else { return }
            reloadDefaults()
            onChange?(.deviceList)
        case kAudioHardwarePropertyDefaultOutputDevice:
            reloadDefaults()
            onChange?(.defaultOutput)
        case kAudioHardwarePropertyDefaultInputDevice:
            reloadDefaults()
            onChange?(.defaultInput)
        default:
            reloadDefaults()
            onChange?(.systemOutput)
        }
    }

    /// Returns whether the visible device list changed.
    @discardableResult
    private func reloadDevices() -> Bool {
        let visible = AudioDevice.all().filter { !$0.uid.hasPrefix(ProcessTapSession.aggregateUIDPrefix) }
        guard visible != devices else { return false }
        devices = visible
        return true
    }

    private func reloadDefaults() {
        let system = AudioObjectID.system
        defaultOutputID = system.read(.init(kAudioHardwarePropertyDefaultOutputDevice), initial: AudioObjectID.unknown) ?? .unknown
        defaultInputID = system.read(.init(kAudioHardwarePropertyDefaultInputDevice), initial: AudioObjectID.unknown) ?? .unknown
        systemOutputID = system.read(.init(kAudioHardwarePropertyDefaultSystemOutputDevice), initial: AudioObjectID.unknown) ?? .unknown

        if listenedOutputID != defaultOutputID {
            listenedOutputID = defaultOutputID
            outputListeners = listeners(on: defaultOutputID, scope: kAudioObjectPropertyScopeOutput, selectors: [
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                kAudioHardwareServiceDeviceProperty_VirtualMainBalance,
                kAudioDevicePropertyVolumeScalar,
                kAudioDevicePropertyMute,
                kAudioDevicePropertyNominalSampleRate,
            ]) { [weak self] in self?.refreshOutputState() }
        }
        if listenedInputID != defaultInputID {
            listenedInputID = defaultInputID
            inputVolumeBeforeSoftMute = nil
            inputListeners = listeners(on: defaultInputID, scope: kAudioObjectPropertyScopeInput, selectors: [
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                kAudioDevicePropertyVolumeScalar,
                kAudioDevicePropertyMute,
            ]) { [weak self] in self?.refreshInputState() }
        }
        refreshOutputState()
        refreshInputState()
    }

    private func listeners(on device: AudioObjectID,
                           scope: AudioObjectPropertyScope,
                           selectors: [AudioObjectPropertySelector],
                           handler: @escaping () -> Void) -> [PropertyListener] {
        guard device.isValid else { return [] }
        return selectors.compactMap { selector in
            let address = AudioObjectPropertyAddress(selector, scope)
            return device.hasProperty(address) ? PropertyListener(objectID: device, address: address, handler: handler) : nil
        }
    }

    private func refreshOutputState() {
        let device = defaultOutputID
        let scope = kAudioObjectPropertyScopeOutput
        outputVolumeAvailable = Self.isVolumeSettable(device, scope: scope)
        outputVolume = Self.readVolume(device, scope: scope) ?? 0
        outputMuted = (device.read(.init(kAudioDevicePropertyMute, scope), initial: UInt32(0)) ?? 0) != 0

        let balance = AudioObjectPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainBalance, scope)
        outputBalanceAvailable = device.isPropertySettable(balance)
        outputBalance = (device.read(balance, initial: Float32(0.5)) ?? 0.5) * 2 - 1

        outputSampleRate = device.read(.init(kAudioDevicePropertyNominalSampleRate), initial: Float64(0)) ?? 0
        let ranges = device.readArray(.init(kAudioDevicePropertyAvailableNominalSampleRates), of: AudioValueRange.self)
        let common: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
        var rates = Set<Double>()
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                rates.insert(range.mMinimum)
            } else {
                common.filter { $0 >= range.mMinimum && $0 <= range.mMaximum }.forEach { rates.insert($0) }
            }
        }
        outputSampleRates = rates.sorted()
    }

    private func refreshInputState() {
        let device = defaultInputID
        let scope = kAudioObjectPropertyScopeInput
        inputVolumeAvailable = Self.isVolumeSettable(device, scope: scope)
        let volume = Self.readVolume(device, scope: scope) ?? 0
        let hardwareMute = (device.read(.init(kAudioDevicePropertyMute, scope), initial: UInt32(0)) ?? 0) != 0
        if inputVolumeBeforeSoftMute != nil {
            inputMuted = true
        } else {
            inputVolume = volume
            inputMuted = hardwareMute
        }
    }

    // MARK: Volume helpers (virtual main volume → main element → per-channel fallback)

    nonisolated static func readVolume(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Float? {
        guard device.isValid else { return nil }
        let virtual = AudioObjectPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        if device.hasProperty(virtual), let value = device.read(virtual, initial: Float32(0)) { return value }
        let main = AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope)
        if device.hasProperty(main), let value = device.read(main, initial: Float32(0)) { return value }
        let channels = (1...2).compactMap { channel -> Float32? in
            let address = AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope, AudioObjectPropertyElement(channel))
            return device.hasProperty(address) ? device.read(address, initial: Float32(0)) : nil
        }
        return channels.isEmpty ? nil : channels.reduce(0, +) / Float(channels.count)
    }

    nonisolated static func isVolumeSettable(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        guard device.isValid else { return false }
        return volumeAddresses(device, scope: scope).contains { device.isPropertySettable($0) }
    }

    nonisolated static func writeVolume(_ device: AudioObjectID, scope: AudioObjectPropertyScope, value: Float) {
        guard device.isValid else { return }
        for address in volumeAddresses(device, scope: scope) where device.isPropertySettable(address) {
            device.write(address, value: Float32(value))
            if address.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume
                || address.mElement == kAudioObjectPropertyElementMain { return }
        }
    }

    nonisolated private static func volumeAddresses(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> [AudioObjectPropertyAddress] {
        [
            AudioObjectPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope),
            AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope),
            AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope, 1),
            AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope, 2),
        ].filter { device.hasProperty($0) }
    }

    // MARK: Preview

    private func loadPreviewState() {
        devices = PreviewData.devices
        defaultOutputID = 1
        defaultInputID = 2
        systemOutputID = 1
        outputVolume = 0.38
        outputVolumeAvailable = true
        outputBalanceAvailable = true
        outputSampleRate = 48_000
        outputSampleRates = [44_100, 48_000, 96_000]
        inputVolume = 0.2
        inputVolumeAvailable = true
        alertVolume = 1
    }
}
