import SwiftUI

struct SettingsView: View {
    @Environment(AudioEngine.self) private var engine
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in LoginItem.setEnabled(enabled) }
                Picker("Header badge", selection: preference(\.edition)) {
                    ForEach(Edition.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Picker("Capture", selection: preference(\.captureMode)) {
                    ForEach(CaptureMode.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("System Audio Recording") {
                    HStack(spacing: 8) {
                        Text(permissionText).foregroundStyle(.secondary)
                        if engine.permission != .authorized {
                            Button(engine.permission == .denied ? "Open Settings" : "Request Access") {
                                engine.requestCapturePermission()
                            }
                        }
                    }
                }
                Toggle("Show microphone input level", isOn: preference(\.showInputLevel))
            } header: {
                Text("Per-App Audio")
            } footer: {
                Text("Apps are captured with Core Audio process taps (macOS 14.2+). Showing the microphone level keeps the input open while the panel is visible, which lights the mic indicator.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All App Settings…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 400)
        .confirmationDialog("Reset volume, effects and routing for every app?", isPresented: $confirmReset) {
            Button("Reset All", role: .destructive) { engine.resetAllApps() }
        }
        .onAppear { engine.recheckPermission() }
    }

    private var permissionText: String {
        switch engine.permission {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .unknown: "Not determined"
        }
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(get: { engine.prefs[keyPath: keyPath] },
                set: { engine.prefs[keyPath: keyPath] = $0 })
    }
}
