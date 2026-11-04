import Foundation

struct EQSettings: Codable, Equatable {
    var enabled = false
    var gains = [Float](repeating: 0, count: EQBands.count)
    var presetName: String? = "Flat"

    var isActive: Bool { enabled && gains.contains { abs($0) > 0.05 } }
}

/// Everything the user can change for one app. Stored per bundle identifier.
struct AppAudioSettings: Codable, Equatable {
    /// Slider position: 0 … 2 (1 = 100 %, above 1 is boost).
    var volume: Float = 1
    var isMuted = false
    /// -1 (left) … +1 (right)
    var balance: Float = 0
    var eq = EQSettings()
    /// nil follows the system default output device.
    var outputDeviceUID: String?
    var outputDeviceName: String?

    var isAdjusted: Bool {
        abs(volume - 1) > 0.001 || isMuted || abs(balance) > 0.001 || eq.isActive || outputDeviceUID != nil
    }
}

struct FavoriteApp: Codable, Hashable, Identifiable {
    var id: String          // bundle identifier
    var name: String
    var bundlePath: String?
}

enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    /// Every app that plays audio is captured, which also powers its level meter.
    case allActive
    /// Only apps whose settings differ from the defaults are captured (no meters for the rest).
    case adjustedOnly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .allActive: "All apps that play audio"
        case .adjustedOnly: "Only apps I adjust"
        }
    }
}

enum Edition: String, Codable, CaseIterable, Identifiable {
    case pro, trial
    var id: String { rawValue }
    var title: String { self == .pro ? "Pro" : "Trial Mode" }
}

struct Preferences: Codable, Equatable {
    var systemExpanded = true
    var applicationsExpanded = true
    var showRouting = true
    var captureMode: CaptureMode = .allActive
    var showInputLevel = false
    var edition: Edition = .pro
}

struct QuickConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var created = Date()
    var apps: [String: AppAudioSettings]
    var outputDeviceUID: String?
    var inputDeviceUID: String?
    var soundEffectsDeviceUID: String?
    var outputVolume: Float?
    var inputVolume: Float?
    var systemEQ: EQSettings?
}

struct PersistedState: Codable {
    var apps: [String: AppAudioSettings] = [:]
    var favorites: [FavoriteApp] = []
    var quickConfigs: [QuickConfig] = []
    var systemEQ = EQSettings()
    var prefs = Preferences()

    private static let defaultsKey = "SoundSourceClone.state.v1"

    static func load() -> PersistedState {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return PersistedState() }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
