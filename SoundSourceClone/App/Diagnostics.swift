import AppKit
import CoreAudio

/// `SoundSourceClone --diagnose` prints what the engine would see, without creating any taps.
@MainActor
enum Diagnostics {
    static func run() {
        let devices = AudioDeviceManager()
        devices.start()
        print("== Devices ==")
        for device in devices.devices {
            var roles: [String] = []
            if device.id == devices.defaultOutputID { roles.append("default output") }
            if device.id == devices.defaultInputID { roles.append("default input") }
            if device.id == devices.systemOutputID { roles.append("sound effects") }
            print("  [\(device.id)] \(device.name)  in:\(device.inputChannels) out:\(device.outputChannels)  uid:\(device.uid)"
                  + (roles.isEmpty ? "" : "  <- \(roles.joined(separator: ", "))"))
        }
        print("Output volume: \(devices.outputVolumeAvailable ? Theme.percent(devices.outputVolume) : "n/a")"
              + (devices.outputMuted ? " (muted)" : "")
              + "  sample rate: \(devices.outputSampleRate) Hz  rates: \(devices.outputSampleRates)")
        print("Input volume:  \(devices.inputVolumeAvailable ? Theme.percent(devices.inputVolume) : "n/a")"
              + (devices.inputMuted ? " (muted)" : ""))
        print("Alert volume:  \(Theme.percent(devices.alertVolume))")

        let permission: String
        switch CapturePermission.status {
        case .authorized: permission = "authorized"
        case .denied: permission = "denied"
        case .unknown: permission = CapturePermission.canRequest ? "not determined" : "unknown (TCC SPI unavailable)"
        }
        print("System Audio Recording permission: \(permission)")

        let processIDs = AudioObjectID.system.readArray(.init(kAudioHardwarePropertyProcessObjectList), of: AudioObjectID.self)
        let resolver = AppIdentityResolver()
        var groups: [String: [String]] = [:]
        var unresolved: [String] = []
        for id in processIDs {
            guard let pid = id.read(.init(kAudioProcessPropertyPID), initial: pid_t(-1)), pid > 0 else { continue }
            let bundleID = id.readString(.init(kAudioProcessPropertyBundleID))
            let playing = (id.read(.init(kAudioProcessPropertyIsRunningOutput), initial: UInt32(0)) ?? 0) != 0
            let process = AudioProcess(objectID: id, pid: pid, bundleID: bundleID, isRunningOutput: playing)
            let label = "pid \(pid) \(bundleID ?? "?")\(playing ? " ▶︎ playing" : "")"
            if let identity = resolver.identity(for: process) {
                groups["\(identity.name) (\(identity.id))", default: []].append(label)
            } else {
                unresolved.append(label)
            }
        }
        print("== Audio processes → apps (\(processIDs.count) process objects) ==")
        for (app, members) in groups.sorted(by: { $0.key < $1.key }) {
            print("  \(app)")
            members.forEach { print("      \($0)") }
        }
        print("  (not shown as apps: \(unresolved.count))")
        unresolved.prefix(12).forEach { print("      \($0)") }
    }
}
