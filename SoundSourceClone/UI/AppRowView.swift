import SwiftUI

struct AppRowView: View {
    @Environment(AudioEngine.self) private var engine
    let app: AppEntry
    @State private var expansion: RowExpansion?
    @State private var isHovering = false

    init(app: AppEntry, initialExpansion: RowExpansion? = nil) {
        self.app = app
        _expansion = State(initialValue: initialExpansion)
    }

    var body: some View {
        VStack(spacing: 0) {
            row
                .background(isHovering ? Theme.hover : Color.clear)
                .onHover { isHovering = $0 }
            switch expansion {
            case .effects:
                EqualizerPanel(title: "\(app.name) Equalizer", settings: app.settings.eq) {
                    engine.setEQ($0, for: app)
                }
            case .details:
                AppDetailsPanel(app: app)
            case nil:
                EmptyView()
            }
        }
    }

    private var row: some View {
        let settings = app.settings
        return MixerRow(
            title: app.name,
            isDimmed: !app.isPlaying,
            percentText: settings.isMuted ? "Muted" : Theme.percent(settings.volume),
            slider: VolumeSlider(
                value: Binding(get: { settings.isMuted ? 0 : settings.volume },
                               set: { engine.setVolume($0, for: app) }),
                maxValue: 2,
                defaultValue: 1,
                level: app.level,
                isDimmed: settings.isMuted || !app.isRunning)
        ) {
            StarButton(isOn: app.isFavorite) { engine.toggleFavorite(app) }
        } icon: {
            AppIconButton(icon: app.icon, isMuted: settings.isMuted) { engine.toggleMute(app) }
        } trailing: {
            IconButton(systemName: "slider.vertical.3",
                       isOn: expansion == .effects,
                       isActive: settings.eq.isActive,
                       help: "Equalizer & effects") { toggle(.effects) }
            if engine.prefs.showRouting {
                routingPicker
            }
            ChevronButton(isOpen: expansion == .details, help: "App details") { toggle(.details) }
        }
    }

    private var routingPicker: some View {
        let devices = engine.devices
        let settings = app.settings
        let routed = settings.outputDeviceUID.flatMap { devices.device(uid: $0) }
        let isMissing = settings.outputDeviceUID != nil && routed == nil
        // Not redirected: the app plays wherever it chose, normally the system default.
        let unrouted = app.nativeOutputDeviceID.flatMap { devices.device(id: $0) } ?? devices.defaultOutput
        let followsDefault = unrouted == nil || unrouted?.id == devices.defaultOutputID
        let title: String
        if let routed {
            title = routed.name
        } else if isMissing {
            title = "\(settings.outputDeviceName ?? "Device") (offline)"
        } else {
            title = followsDefault ? "Default Output" : (unrouted?.name ?? "Default Output")
        }
        let symbol = routed?.outputSymbol ?? (isMissing ? "exclamationmark.triangle.fill" : "arrow.uturn.right")
        let unroutedTitle = followsDefault
            ? "Default Output (\(devices.defaultOutput?.name ?? "none"))"
            : "App's Own Output (\(unrouted?.name ?? "unknown"))"

        return DevicePickerButton(title: title, symbol: symbol, isMissing: isMissing) {
            var items: [MenuItemSpec] = [
                .action(unroutedTitle,
                        symbol: "arrow.uturn.right",
                        checked: settings.outputDeviceUID == nil) { engine.setOutputDevice(nil, for: app) },
                .separator,
                .header("Route \(app.name) To"),
            ]
            items += devices.outputDevices.map { device in
                .action(device.name, symbol: device.outputSymbol, checked: device.uid == settings.outputDeviceUID) {
                    engine.setOutputDevice(device, for: app)
                }
            }
            if isMissing {
                items.append(.note("\(settings.outputDeviceName ?? "Previous device") — not connected",
                                   symbol: "exclamationmark.triangle"))
            }
            return items
        }
    }

    private func toggle(_ target: RowExpansion) {
        expansion = expansion == target ? nil : target
    }
}
