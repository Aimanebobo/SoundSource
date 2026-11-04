import AppKit
import CoreAudio
import Observation

/// One row in the Applications section: a running app (possibly several processes) or a favorite.
@MainActor @Observable
final class AppEntry: Identifiable {
    let id: String
    var name: String
    var icon: NSImage
    var bundleID: String?
    var bundleURL: URL?
    var settings: AppAudioSettings

    var isFavorite = false
    var isRegularApp = false
    var isRunning = false
    var isPlaying = false
    var isCaptured = false
    var captureError: String?
    /// Post-processing peak, mapped to 0…1 on a −60…0 dBFS scale.
    var level: Float = 0
    var processObjectIDs: [AudioObjectID] = []
    var pids: [pid_t] = []
    /// The device the app itself is playing to (usually the system default, unless the app picked one).
    var nativeOutputDeviceID: AudioObjectID?

    init(id: String, name: String, icon: NSImage, bundleID: String?, bundleURL: URL?, settings: AppAudioSettings) {
        self.id = id
        self.name = name
        self.icon = icon
        self.bundleID = bundleID
        self.bundleURL = bundleURL
        self.settings = settings
    }
}
