import AppKit
import SwiftUI

/// Opened by an app row's chevron.
struct AppDetailsPanel: View {
    @Environment(AudioEngine.self) private var engine
    let app: AppEntry

    var body: some View {
        DetailCard {
            HStack(spacing: 8) {
                DetailLabel("Balance")
                Text("L").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                BalanceSlider(value: Binding(get: { app.settings.balance },
                                             set: { engine.setBalance($0, for: app) }))
                    .frame(width: 200)
                Text("R").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                Text(balanceText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, alignment: .leading)
                Spacer()
            }

            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            HStack(spacing: 8) {
                CapsuleButton(app.settings.isMuted ? "Unmute" : "Mute",
                              symbol: app.settings.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                    engine.toggleMute(app)
                }
                CapsuleButton("Reset", symbol: "arrow.counterclockwise") { engine.reset(app) }
                if let url = app.bundleURL {
                    CapsuleButton("Show in Finder", symbol: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Spacer()
                if let bundleID = app.bundleID {
                    Text(bundleID)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var balanceText: String {
        let balance = app.settings.balance
        if abs(balance) < 0.005 { return "Centre" }
        return "\(Int((abs(balance) * 100).rounded()))% \(balance < 0 ? "L" : "R")"
    }

    private var statusColor: Color {
        if app.captureError != nil { return Theme.danger }
        if app.isCaptured { return Color.green }
        return Theme.tertiaryText
    }

    private var statusText: String {
        if let error = app.captureError { return "Capture failed: \(error)" }
        if app.isCaptured {
            let count = app.pids.count
            let pids = app.pids.prefix(4).map(String.init).joined(separator: ", ")
            return "Processing via Core Audio process tap · \(count) process\(count == 1 ? "" : "es") (PID \(pids))"
        }
        if !app.isRunning { return "Not running — settings apply the next time it plays audio." }
        if !engine.canCapture { return "Waiting for System Audio Recording permission." }
        if app.processObjectIDs.isEmpty { return "Running, but it hasn't opened an audio connection yet." }
        return "Passthrough — change a setting to start processing this app."
    }
}

/// Opened by the System › Output chevron.
struct OutputDetailsPanel: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        let devices = engine.devices
        DetailCard {
            HStack(spacing: 8) {
                DetailLabel("Sample Rate")
                PopUpMenuButton(items: sampleRateItems) {
                    CapsuleLabel(title: Self.format(rate: devices.outputSampleRate), symbol: "waveform", showsChevron: true)
                }
                .disabled(devices.outputSampleRates.count < 2)
                Spacer()
                if let output = devices.defaultOutput {
                    Text("\(output.outputChannels) ch · \(output.uid)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 8) {
                DetailLabel("Balance")
                Text("L").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                BalanceSlider(value: Binding(get: { devices.outputBalance }, set: { devices.setOutputBalance($0) }),
                              isEnabled: devices.outputBalanceAvailable)
                    .frame(width: 200)
                Text("R").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                if !devices.outputBalanceAvailable {
                    Text("Not supported by this device")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                CapsuleButton("Sound Settings…", symbol: "gear") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
                CapsuleButton("Audio MIDI Setup", symbol: "pianokeys") {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"),
                                                       configuration: NSWorkspace.OpenConfiguration())
                }
                Spacer()
            }
        }
    }

    private func sampleRateItems() -> [MenuItemSpec] {
        let devices = engine.devices
        return [.header("Sample Rate")] + devices.outputSampleRates.map { rate in
            .action(Self.format(rate: rate), checked: abs(rate - devices.outputSampleRate) < 1) {
                devices.setOutputSampleRate(rate)
            }
        }
    }

    static func format(rate: Double) -> String {
        guard rate > 0 else { return "—" }
        let khz = rate / 1000
        return khz == khz.rounded() ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz)
    }
}

private struct DetailLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 74, alignment: .leading)
    }
}
