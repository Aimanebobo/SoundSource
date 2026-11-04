import SwiftUI

struct HeaderView: View {
    @Environment(AudioEngine.self) private var engine
    @Environment(PanelState.self) private var panel

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(nsImage: Self.logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                Text("SoundSource")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
            }

            HStack(spacing: 4) {
                IconButton(systemName: panel.isPinned ? "pin.fill" : "pin",
                           isOn: panel.isPinned,
                           help: panel.isPinned ? "Unpin (close when clicking elsewhere)" : "Keep window open") {
                    panel.isPinned.toggle()
                }
                IconButton(systemName: "arrow.triangle.branch",
                           isOn: engine.prefs.showRouting,
                           help: "Show per-app audio routing") {
                    engine.prefs.showRouting.toggle()
                }

                Spacer()

                EditionBadge(edition: engine.prefs.edition)
                    .padding(.trailing, 4)
                IconButton(systemName: engine.devices.inputMuted ? "mic.slash.fill" : "mic.fill",
                           isOn: engine.devices.inputMuted,
                           tint: Theme.danger,
                           help: engine.devices.inputMuted ? "Unmute microphone" : "Mute microphone") {
                    engine.devices.toggleInputMute()
                }
                PopUpMenuButton(items: gearMenu) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .help("Settings")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    /// The app icon from Assets.xcassets (AppIcon), the same artwork Finder and the Dock show.
    private static let logo = NSImage(named: NSImage.applicationIconName) ?? NSImage()

    private func gearMenu() -> [MenuItemSpec] {
        [
            .action("Settings…", symbol: "gearshape") { panel.openSettings() },
            .action("Launch at Login", checked: LoginItem.isEnabled) { LoginItem.setEnabled(!LoginItem.isEnabled) },
            .separator,
            .action("About SoundSource Clone", symbol: "info.circle") {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            },
            .action("Quit SoundSource Clone", symbol: "power") { NSApp.terminate(nil) },
        ]
    }
}

struct EditionBadge: View {
    let edition: Edition

    var body: some View {
        Text(edition == .pro ? "PRO" : "Trial Mode")
            .font(.system(size: 9.5, weight: .bold))
            .kerning(edition == .pro ? 0.8 : 0)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(edition == .pro ? Theme.proBadge : Theme.trialBadge))
            .help(edition == .pro ? "Pro" : "Trial Mode")
    }
}
