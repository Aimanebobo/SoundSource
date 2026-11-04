import AppKit
import SwiftUI

struct SystemSectionView: View {
    @Environment(AudioEngine.self) private var engine
    @State private var expansion: RowExpansion?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "System", isExpanded: engine.prefs.systemExpanded) {
                engine.prefs.systemExpanded.toggle()
            }
            if engine.prefs.systemExpanded {
                outputRow
                switch expansion {
                case .effects:
                    EqualizerPanel(title: "System Effects",
                                   settings: engine.systemEQ,
                                   note: "Applied to every captured app, on top of each app's own EQ.") {
                        engine.systemEQ = $0
                    }
                case .details:
                    OutputDetailsPanel()
                case nil:
                    EmptyView()
                }
                inputRow
                soundEffectsRow
            }
        }
        .padding(.bottom, 4)
    }

    private func toggle(_ target: RowExpansion) {
        expansion = expansion == target ? nil : target
    }

    // MARK: Output

    private var outputRow: some View {
        let devices = engine.devices
        let output = devices.defaultOutput
        let percent = !devices.outputVolumeAvailable ? "—" : (devices.outputMuted ? "Muted" : Theme.percent(devices.outputVolume))
        return MixerRow(
            title: "Output",
            percentText: percent,
            slider: VolumeSlider(
                value: Binding(get: { devices.outputMuted ? 0 : devices.outputVolume },
                               set: { devices.setOutputVolume($0) }),
                defaultValue: 0.5,
                level: engine.outputLevel,
                isEnabled: devices.outputVolumeAvailable)
        ) {
            Color.clear
        } icon: {
            SymbolButton(systemName: devices.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                         tint: devices.outputMuted ? Theme.danger : nil,
                         help: devices.outputMuted ? "Unmute output" : "Mute output") {
                devices.toggleOutputMute()
            }
        } trailing: {
            IconButton(systemName: "slider.vertical.3",
                       isOn: expansion == .effects,
                       isActive: engine.systemEQ.isActive,
                       help: "System effects") { toggle(.effects) }
            DevicePickerButton(title: output?.name ?? "No Output Device",
                               symbol: output?.outputSymbol ?? "speaker.slash") {
                DeviceMenus.devices(devices.outputDevices, selectedUID: output?.uid, header: "Output Device",
                                    symbol: \.outputSymbol) { devices.setDefaultOutput($0) }
            }
            ChevronButton(isOpen: expansion == .details, help: "Output device options") { toggle(.details) }
        }
    }

    // MARK: Input

    private var inputRow: some View {
        let devices = engine.devices
        let input = devices.defaultInput
        let percent = !devices.inputVolumeAvailable ? "—" : (devices.inputMuted ? "Muted" : Theme.percent(devices.inputVolume))
        return MixerRow(
            title: "Input",
            percentText: percent,
            slider: VolumeSlider(
                value: Binding(get: { devices.inputMuted ? 0 : devices.inputVolume },
                               set: { devices.setInputVolume($0) }),
                defaultValue: 0.5,
                level: engine.inputLevel,
                showsMeter: engine.prefs.showInputLevel,
                isEnabled: devices.inputVolumeAvailable)
        ) {
            Color.clear
        } icon: {
            SymbolButton(systemName: devices.inputMuted ? "mic.slash.fill" : "mic.fill",
                         tint: devices.inputMuted ? Theme.danger : nil,
                         help: devices.inputMuted ? "Unmute microphone" : "Mute microphone") {
                devices.toggleInputMute()
            }
        } trailing: {
            ColumnSpacer(width: 22)
            DevicePickerButton(title: input?.name ?? "No Input Device",
                               symbol: input?.inputSymbol ?? "mic.slash") {
                DeviceMenus.devices(devices.inputDevices, selectedUID: input?.uid, header: "Input Device",
                                    symbol: \.inputSymbol) { devices.setDefaultInput($0) }
            }
            ColumnSpacer(width: 18)
        }
    }

    // MARK: Sound effects

    private var soundEffectsRow: some View {
        let devices = engine.devices
        let effectsDevice = devices.systemOutput
        return MixerRow(
            title: "Sound Effects",
            percentText: Theme.percent(devices.alertVolume),
            slider: VolumeSlider(
                value: Binding(get: { devices.alertVolume }, set: { devices.setAlertVolume($0) }),
                showsMeter: false,
                onEditingEnded: { NSSound.beep() })
        ) {
            Color.clear
        } icon: {
            SymbolButton(systemName: "bell.fill", help: "Play alert sound") { NSSound.beep() }
        } trailing: {
            ColumnSpacer(width: 22)
            DevicePickerButton(title: effectsDevice?.name ?? "System Output",
                               symbol: effectsDevice?.outputSymbol ?? "bell") {
                DeviceMenus.devices(devices.outputDevices, selectedUID: effectsDevice?.uid,
                                    header: "Play Sound Effects Through",
                                    symbol: \.outputSymbol) { devices.setSoundEffectsOutput($0) }
            }
            ColumnSpacer(width: 18)
        }
    }
}

@MainActor
enum DeviceMenus {
    static func devices(_ devices: [AudioDevice],
                        selectedUID: String?,
                        header: String,
                        symbol: KeyPath<AudioDevice, String>,
                        onSelect: @escaping (AudioDevice) -> Void) -> [MenuItemSpec] {
        var items: [MenuItemSpec] = [.header(header)]
        if devices.isEmpty { items.append(.note("No devices available")) }
        items += devices.map { device in
            .action(device.name, symbol: device[keyPath: symbol], checked: device.uid == selectedUID) { onSelect(device) }
        }
        items += [
            .separator,
            .action("Sound Settings…", symbol: "gear") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
            },
        ]
        return items
    }
}
