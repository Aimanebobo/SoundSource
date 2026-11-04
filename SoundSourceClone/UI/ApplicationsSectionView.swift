import SwiftUI

struct ApplicationsSectionView: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Applications", detail: detail, isExpanded: engine.prefs.applicationsExpanded) {
                engine.prefs.applicationsExpanded.toggle()
            }
            if engine.prefs.applicationsExpanded {
                if !engine.canCapture { PermissionBanner() }
                if engine.apps.isEmpty {
                    EmptyAppsView()
                } else {
                    ForEach(engine.apps) { app in
                        AppRowView(app: app,
                                   initialExpansion: engine.previewExpandedAppID == app.id ? .effects : nil)
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    private var detail: String? {
        let playing = engine.apps.filter(\.isPlaying).count
        return playing > 0 ? "\(playing) playing" : nil
    }
}

private struct EmptyAppsView: View {
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "music.note.list")
                .font(.system(size: 18))
                .foregroundStyle(Theme.tertiaryText)
            Text("No apps are playing audio")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Text("Apps appear here as soon as they make sound. Star an app to keep it listed.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct PermissionBanner: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        let denied = engine.permission == .denied
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Per-app audio needs System Audio Recording access")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(denied
                     ? "Enable SoundSource in System Settings › Privacy & Security › Screen & System Audio Recording."
                     : "Allow access to change app volumes, apply effects and route apps to other devices.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            CapsuleButton(denied ? "Open Settings" : "Grant Access", isProminent: true) {
                engine.requestCapturePermission()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.warning.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.warning.opacity(0.3), lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
