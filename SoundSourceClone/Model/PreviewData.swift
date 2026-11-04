import AppKit
import CoreAudio

/// Static data for SwiftUI previews and `--snapshot` renders. No Core Audio calls are made with it.
enum PreviewData {
    static let devices: [AudioDevice] = [
        AudioDevice(id: 1, uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers",
                    transportType: kAudioDeviceTransportTypeBuiltIn, inputChannels: 0, outputChannels: 2, inputStreamCount: 0),
        AudioDevice(id: 2, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone",
                    transportType: kAudioDeviceTransportTypeBuiltIn, inputChannels: 1, outputChannels: 0, inputStreamCount: 1),
        AudioDevice(id: 3, uid: "AirPodsPro", name: "AirPods Pro",
                    transportType: kAudioDeviceTransportTypeBluetooth, inputChannels: 1, outputChannels: 2, inputStreamCount: 1),
        AudioDevice(id: 4, uid: "LGUltraFine", name: "LG UltraFine Display Audio",
                    transportType: kAudioDeviceTransportTypeUSB, inputChannels: 0, outputChannels: 2, inputStreamCount: 0),
        AudioDevice(id: 5, uid: "BlackHole2ch", name: "BlackHole 2ch",
                    transportType: kAudioDeviceTransportTypeVirtual, inputChannels: 2, outputChannels: 2, inputStreamCount: 1),
    ]

    struct App {
        let id: String
        let name: String
        let symbol: String
        var volume: Float = 1
        var level: Float = 0
        var playing = true
        var favorite = false
        var running = true
        var eq: [Float]?
        var outputUID: String?
        var muted = false
    }

    static let apps: [App] = [
        App(id: "com.spotify.client", name: "Spotify", symbol: "music.note", volume: 0.75, level: 0.64, favorite: true),
        App(id: "com.google.Chrome", name: "Google Chrome", symbol: "globe", volume: 1, level: 0.41, favorite: true, outputUID: "AirPodsPro"),
        App(id: "net.whatsapp.WhatsApp", name: "WhatsApp", symbol: "message.fill", volume: 0.5, playing: false, favorite: true),
        App(id: "com.hnc.Discord", name: "Discord", symbol: "bubble.left.and.bubble.right.fill", volume: 1.25, level: 0.72,
            eq: [0, 0, 0, 1, 3, 4, 3, 1, 0, 0]),
        App(id: "com.valvesoftware.steam", name: "Steam", symbol: "gamecontroller.fill", volume: 0.3, level: 0.22),
        App(id: "com.apple.Music", name: "Music", symbol: "music.quarternote.3", playing: false, favorite: true, running: false),
    ]

    static let expandedAppID = "com.hnc.Discord"

    static var state: PersistedState {
        var state = PersistedState()
        state.favorites = apps.filter(\.favorite).map { FavoriteApp(id: $0.id, name: $0.name) }
        state.quickConfigs = [QuickConfig(name: "Gaming", apps: [:]), QuickConfig(name: "Calls", apps: [:])]
        return state
    }

    @MainActor
    static func icon(for app: App) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        let symbol = NSImage(systemSymbolName: app.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        let colors: [NSColor] = [.systemGreen, .systemBlue, .systemTeal, .systemIndigo, .systemGray, .systemPink]
        let color = colors[app.id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % colors.count]
        return NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7).fill()
            let size = symbol.size
            symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                   width: size.width, height: size.height))
            return true
        }
    }
}
