import CoreAudio
import Foundation

/// A Core Audio process object: one OS process that has an audio client connection to the HAL.
struct AudioProcess: Hashable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
    /// Devices the process is currently sending output to (an app may pick its own, e.g. Zoom → headset).
    var outputDeviceIDs: [AudioObjectID] = []
}

/// Tracks `kAudioHardwarePropertyProcessObjectList` (macOS 14+) and each process's output activity.
@MainActor
final class AudioProcessMonitor {
    private(set) var processes: [AudioProcess] = []
    var onChange: (() -> Void)?

    private var listListener: PropertyListener?
    private var activityListeners: [AudioObjectID: [PropertyListener]] = [:]
    private var reloadScheduled = false

    func start() {
        listListener = PropertyListener(objectID: .system, address: .init(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
            self?.scheduleReload()
        }
        reload()
    }

    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadScheduled = false
                self?.reload()
            }
        }
    }

    private func reload() {
        let ids = AudioObjectID.system.readArray(.init(kAudioHardwarePropertyProcessObjectList), of: AudioObjectID.self)
        var result: [AudioProcess] = []
        for id in ids {
            guard let pid = id.read(.init(kAudioProcessPropertyPID), initial: pid_t(-1)), pid > 0 else { continue }
            let running = (id.read(.init(kAudioProcessPropertyIsRunningOutput), initial: UInt32(0)) ?? 0) != 0
            let devices = id.readArray(.init(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput),
                                       of: AudioObjectID.self)
            result.append(AudioProcess(objectID: id,
                                       pid: pid,
                                       bundleID: id.readString(.init(kAudioProcessPropertyBundleID)),
                                       isRunningOutput: running,
                                       outputDeviceIDs: devices))
            if activityListeners[id] == nil {
                activityListeners[id] = [
                    AudioObjectPropertyAddress(kAudioProcessPropertyIsRunningOutput),
                    AudioObjectPropertyAddress(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput),
                ].map { address in
                    PropertyListener(objectID: id, address: address) { [weak self] in self?.scheduleReload() }
                }
            }
        }
        let alive = Set(ids)
        for id in activityListeners.keys where !alive.contains(id) {
            activityListeners[id] = nil
        }
        if result != processes {
            processes = result
            onChange?()
        }
    }
}
