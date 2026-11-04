import CoreAudio
import Foundation

/// Captures one app's audio with a Core Audio process tap (macOS 14.2+) and plays it back,
/// processed, on any output device:
///
///     app processes ──▶ CATapDescription (stereo mixdown, muted at the source while tapped)
///                                │
///     private aggregate device = [output device] + [tap]  (drift-compensated)
///                                │  IOProc: tap input ─▶ StereoProcessor ─▶ device output
///                                ▼
///                         chosen output device
///
/// If this process dies the HAL destroys the tap and the app's audio returns to normal untouched.
final class ProcessTapSession {
    static let aggregateUIDPrefix = "com.example.SoundSourceClone.tap."

    let appID: String
    let processor = StereoProcessor()
    private(set) var processObjectIDs: [AudioObjectID] = []
    private(set) var outputDeviceUID: String?
    /// Human-readable stream layout of the running aggregate, for logs.
    private(set) var formatSummary = ""

    private var tapDescription: CATapDescription?
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRateListener: PropertyListener?

    var isRunning: Bool { ioProcID != nil }

    init(appID: String) {
        self.appID = appID
    }

    deinit { stop() }

    func start(processes: [AudioObjectID], output: AudioDevice) throws {
        stop()
        try createTap(processes: processes)
        do {
            try startAggregate(output: output)
        } catch {
            destroyTap()
            throw error
        }
    }

    /// Re-targets the existing tap when an app spawns or loses audio helper processes.
    func updateProcesses(_ processes: [AudioObjectID]) throws {
        guard let description = tapDescription, tapID.isValid else {
            throw CoreAudioError(status: OSStatus(kAudioHardwareBadObjectError), operation: "Update tap")
        }
        description.processes = processes
        try caCheck(tapID.write(.init(kAudioTapPropertyDescription), value: description), "Update tap processes")
        processObjectIDs = processes
    }

    /// Rebuilds only the aggregate device; the tap (and the source mute) stays in place.
    func switchOutput(to output: AudioDevice) throws {
        guard tapID.isValid else {
            throw CoreAudioError(status: OSStatus(kAudioHardwareBadObjectError), operation: "Switch output")
        }
        stopAggregate()
        try startAggregate(output: output)
    }

    func stop() {
        stopAggregate()
        destroyTap()
    }

    // MARK: Tap

    private func createTap(processes: [AudioObjectID]) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "SoundSource Clone – \(appID)"
        description.isPrivate = true
        // Muted only while our IOProc is reading, so a stalled or crashed engine never silences the app.
        description.muteBehavior = .mutedWhenTapped
        var newTap = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateProcessTap(description, &newTap), "Create process tap")
        tapID = newTap
        tapDescription = description
        processObjectIDs = processes
    }

    private func destroyTap() {
        if tapID.isValid { AudioHardwareDestroyProcessTap(tapID) }
        tapID = .unknown
        tapDescription = nil
        processObjectIDs = []
    }

    // MARK: Aggregate device + IOProc

    private func startAggregate(output: AudioDevice) throws {
        guard let tapDescription else { return }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoundSource Clone (\(appID))",
            kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: output.uid],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ],
            ],
        ]
        var newAggregate = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregate), "Create aggregate device")
        aggregateID = newAggregate

        let rate = newAggregate.read(.init(kAudioDevicePropertyNominalSampleRate), initial: Float64(0)) ?? 0
        processor.prepare(sampleRate: rate > 0 ? rate : 48_000)

        let processor = self.processor
        var procID: AudioDeviceIOProcID?
        // A nil queue runs the block directly on the device's real-time IO thread.
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, newAggregate, nil) { _, inputData, _, outputData, _ in
            processor.render(input: inputData, output: outputData)
        }
        guard status == noErr, let procID else {
            destroyAggregateDevice()
            throw CoreAudioError(status: status, operation: "Create IO proc")
        }
        ioProcID = procID

        if output.inputStreamCount > 0 {
            disableSubDeviceInputStreams(procID: procID, subDeviceStreams: output.inputStreamCount)
        }

        let startStatus = AudioDeviceStart(newAggregate, procID)
        guard startStatus == noErr else {
            stopAggregate()
            throw CoreAudioError(status: startStatus, operation: "Start aggregate device")
        }
        outputDeviceUID = output.uid
        let tapFormat = tapID.read(.init(kAudioTapPropertyFormat), initial: AudioStreamBasicDescription())
        formatSummary = "aggregate \(newAggregate.channelCount(scope: kAudioObjectPropertyScopeInput)) in / "
            + "\(newAggregate.channelCount(scope: kAudioObjectPropertyScopeOutput)) out @ \(Int(processor.sampleRate)) Hz, "
            + "tap \(tapFormat.map { "\($0.mChannelsPerFrame) ch @ \(Int($0.mSampleRate)) Hz" } ?? "format unknown")"

        sampleRateListener = PropertyListener(objectID: newAggregate, address: .init(kAudioDevicePropertyNominalSampleRate)) { [weak self] in
            guard let self, self.aggregateID.isValid,
                  let rate = self.aggregateID.read(.init(kAudioDevicePropertyNominalSampleRate), initial: Float64(0)),
                  rate > 0 else { return }
            self.processor.prepare(sampleRate: rate)
        }
    }

    /// Output devices that also have inputs (USB/Bluetooth headsets) would otherwise have their
    /// microphone opened by the aggregate — lighting the mic indicator and forcing Bluetooth
    /// headsets into low-quality hands-free mode. Only the tap's input stream is needed.
    private func disableSubDeviceInputStreams(procID: AudioDeviceIOProcID, subDeviceStreams: Int) {
        let streams = aggregateID.readArray(.init(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput),
                                            of: AudioStreamID.self)
        guard streams.count > subDeviceStreams else { return }
        // struct AudioHardwareIOProcStreamUsage { void *mIOProc; UInt32 mNumberStreams; UInt32 mStreamIsOn[]; }
        let header = MemoryLayout<UnsafeMutableRawPointer>.size + MemoryLayout<UInt32>.size
        let byteCount = header + MemoryLayout<UInt32>.size * streams.count
        let raw = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<UnsafeMutableRawPointer>.alignment)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(streams.count), toByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        for index in streams.indices {
            raw.storeBytes(of: UInt32(index < subDeviceStreams ? 0 : 1),
                           toByteOffset: header + index * MemoryLayout<UInt32>.size,
                           as: UInt32.self)
        }
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        let status = AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(byteCount), raw)
        if status != noErr { NSLog("SoundSourceClone: stream usage not applied (\(status.fourCharCode))") }
    }

    private func stopAggregate() {
        sampleRateListener?.invalidate()
        sampleRateListener = nil
        if let procID = ioProcID, aggregateID.isValid {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        destroyAggregateDevice()
        outputDeviceUID = nil
    }

    private func destroyAggregateDevice() {
        if aggregateID.isValid { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = .unknown
    }
}
