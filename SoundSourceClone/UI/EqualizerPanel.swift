import SwiftUI

/// Inline 10-band graphic EQ with presets, used for both apps and system-wide effects.
struct EqualizerPanel: View {
    let title: String
    let settings: EQSettings
    var note: String?
    let onChange: (EQSettings) -> Void

    init(title: String, settings: EQSettings, note: String? = nil, onChange: @escaping (EQSettings) -> Void) {
        self.title = title
        self.settings = settings
        self.note = note
        self.onChange = onChange
    }

    var body: some View {
        DetailCard {
            HStack(spacing: 10) {
                PillToggle(isOn: settings.enabled) {
                    var updated = settings
                    updated.enabled.toggle()
                    onChange(updated)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(settings.enabled ? "On" : "Bypassed")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                PopUpMenuButton(items: presetItems) {
                    CapsuleLabel(title: settings.presetName ?? "Custom", symbol: "slider.vertical.3", showsChevron: true)
                }
                CapsuleButton("Reset") {
                    var updated = settings
                    updated.gains = [Float](repeating: 0, count: EQBands.count)
                    updated.presetName = "Flat"
                    onChange(updated)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .trailing) {
                    Text("+12").frame(maxHeight: .infinity, alignment: .top)
                    Text("0")
                    Text("−12").frame(maxHeight: .infinity, alignment: .bottom)
                }
                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 24, height: 96)
                .padding(.trailing, 6)

                ForEach(0..<EQBands.count, id: \.self) { band in
                    VStack(spacing: 5) {
                        EQBandSlider(value: gainBinding(band), isEnabled: settings.enabled)
                            .frame(height: 96)
                        Text(EQBands.labels[band])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        Text(gainLabel(band))
                            .font(.system(size: 8.5).monospacedDigit())
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let note {
                Text(note)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    private func gainBinding(_ band: Int) -> Binding<Float> {
        Binding(
            get: { band < settings.gains.count ? settings.gains[band] : 0 },
            set: { newValue in
                var updated = settings
                if updated.gains.count < EQBands.count {
                    updated.gains += [Float](repeating: 0, count: EQBands.count - updated.gains.count)
                }
                updated.gains[band] = newValue
                updated.enabled = true   // touching a band turns the EQ on
                updated.presetName = EQPreset.matching(updated.gains)?.name
                onChange(updated)
            })
    }

    private func gainLabel(_ band: Int) -> String {
        let gain = band < settings.gains.count ? settings.gains[band] : 0
        if abs(gain) < 0.05 { return "0" }
        return String(format: gain > 0 ? "+%.1f" : "%.1f", gain)
    }

    private func presetItems() -> [MenuItemSpec] {
        [.header("Presets")] + EQPreset.all.map { preset in
            .action(preset.name, checked: preset.name == settings.presetName) {
                var updated = settings
                updated.gains = preset.gains
                updated.presetName = preset.name
                updated.enabled = true
                onChange(updated)
            }
        }
    }
}
