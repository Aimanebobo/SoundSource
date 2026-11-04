import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: AudioEngine?
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `SoundSourceClone --snapshot out.png [--expanded]` renders the panel with sample data and exits.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            SnapshotRenderer.render(to: URL(fileURLWithPath: arguments[index + 1]),
                                    expanded: arguments.contains("--expanded"))
            NSApp.terminate(nil)
            return
        }
        if arguments.contains("--diagnose") {
            Diagnostics.run()
            NSApp.terminate(nil)
            return
        }

        // One engine at a time: a second copy (another build, an Xcode run) asks the running one to
        // show its panel and quits, instead of capturing apps a second time.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ownPID }
        if !others.isEmpty {
            Log.ui.notice("Another copy is already running (pid \(others[0].processIdentifier, privacy: .public)); handing off")
            DistributedNotificationCenter.default().postNotificationName(Self.showPanelNotification, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        let engine = AudioEngine()
        self.engine = engine
        engine.start()
        let menuBar = MenuBarController(engine: engine) { [weak self] in self?.showSettings() }
        self.menuBar = menuBar
        DistributedNotificationCenter.default().addObserver(forName: Self.showPanelNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuBar?.revealPanel() }
        }
    }

    private static let showPanelNotification = Notification.Name("com.example.SoundSourceClone.showPanel")

    /// Opening the app again (Finder, Spotlight, `open`) while it runs reveals the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.revealPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.shutdown()
    }

    private func showSettings() {
        guard let engine else { return }
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView().environment(engine))
            let window = NSWindow(contentViewController: controller)
            window.title = "SoundSource Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
