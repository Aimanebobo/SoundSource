import AppKit
import Observation
import SwiftUI

/// UI state shared between the panel's SwiftUI views and the controller that owns the window.
@MainActor @Observable
final class PanelState {
    var isPinned = false
    var maxScrollHeight: CGFloat = 560
    @ObservationIgnored var isSnapshot = false
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var close: () -> Void = {}
}

/// Owns the status item and toggles the floating panel beneath it.
@MainActor
final class MenuBarController: NSObject {
    private let engine: AudioEngine
    private let state = PanelState()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 420))
    private var contentHeight: CGFloat = 420
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?

    init(engine: AudioEngine, openSettings: @escaping () -> Void) {
        self.engine = engine
        super.init()

        state.openSettings = { [weak self] in
            self?.hidePanel(force: true)
            openSettings()
        }
        state.close = { [weak self] in self?.hidePanel(force: true) }
        panel.onContentHeightChange = { [weak self] height in
            MainActor.assumeIsolated { self?.contentHeightChanged(height) }
        }
        panel.setRootView(PopoverRootView().environment(engine).environment(state))

        statusItem.autosaveName = "SoundSourceClone"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "SoundSource"
        }
        trackVolumeForIcon()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.logStatusItemPlacement()
                // `--show-panel` opens the panel at launch (handy when the menu bar icon is hidden).
                // `--dump-panel <path.png>` also renders the live panel to a file two seconds later.
                let arguments = CommandLine.arguments
                let dumpPath = arguments.firstIndex(of: "--dump-panel").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
                if arguments.contains("--show-panel") || dumpPath != nil { self.showPanel() }
                if let dumpPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        MainActor.assumeIsolated { self?.dumpPanel(to: URL(fileURLWithPath: dumpPath)) }
                    }
                }
            }
        }
    }

    private func dumpPanel(to url: URL) {
        let written = panel.writeContentImage(to: url)
        Log.ui.notice("Panel dump \(written ? "written" : "failed", privacy: .public): frame \(NSStringFromRect(self.panel.frame), privacy: .public), SwiftUI ideal height \(self.panel.contentHeight, privacy: .public), visible \(self.panel.isVisible, privacy: .public)")
    }

    private func logStatusItemPlacement() {
        let window = statusItem.button?.window
        let frame = window.map { NSStringFromRect($0.frame) } ?? "none"
        Log.ui.notice("Status item visible: \(self.statusItem.isVisible, privacy: .public), window frame: \(frame, privacy: .public), screen: \(window?.screen?.localizedName ?? "none", privacy: .public), on screen: \(window?.isOnActiveSpace ?? false, privacy: .public)")
    }

    // MARK: Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else if panel.isVisible {
            hidePanel(force: true)
        } else {
            showPanel()
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = MenuBuilder.menu([
            .action("Open SoundSource", symbol: "slider.horizontal.3") { [weak self] in self?.showPanel() },
            .action("Settings…", symbol: "gearshape") { [weak self] in self?.state.openSettings() },
            .separator,
            .action("Quit SoundSource Clone", symbol: "power") { NSApp.terminate(nil) },
        ])
        MenuBuilder.popUp(menu, below: button)
    }

    /// Keeps the menu bar glyph in sync with the output volume using Observation.
    private func trackVolumeForIcon() {
        withObservationTracking {
            updateStatusIcon()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackVolumeForIcon() }
        }
    }

    /// A speaker cabinet rather than the speaker cone, so it can't be mistaken for macOS's own Sound menu.
    private func updateStatusIcon() {
        let devices = engine.devices
        let muted = devices.outputMuted || (devices.outputVolumeAvailable && devices.outputVolume < 0.01)
        let image = NSImage(systemSymbolName: muted ? "speaker.slash.fill" : "hifispeaker.fill",
                            accessibilityDescription: "SoundSource")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.title = image == nil ? "SS" : ""
    }

    // MARK: Panel

    func revealPanel() {
        if !panel.isVisible { showPanel() }
    }

    private func showPanel() {
        engine.devices.refresh()
        engine.recheckPermission()
        engine.beginMetering()
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.highlight(true)
        installMonitors()
    }

    private func hidePanel(force: Bool = false) {
        guard panel.isVisible, force || !state.isPinned else { return }
        panel.orderOut(nil)
        engine.endMetering()
        statusItem.button?.highlight(false)
        removeMonitors()
    }

    /// Header + footer alone are ~85 pt; anything smaller is a layout pass before the content exists.
    private static let minimumHeight: CGFloat = 120

    private func contentHeightChanged(_ height: CGFloat) {
        let rounded = ceil(height)
        Log.ui.debug("Reported content height \(rounded, privacy: .public)")
        guard rounded >= 60, abs(rounded - contentHeight) > 0.5 else { return }
        contentHeight = rounded
        if panel.isVisible { positionPanel() }
    }

    /// Top edge stays pinned just below the menu bar; the panel grows downwards.
    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let chrome: CGFloat = 100   // header + footer + hairlines
        let maxScroll = max(visible.height - chrome - 24, 200)
        if abs(state.maxScrollHeight - maxScroll) > 0.5 { state.maxScrollHeight = maxScroll }

        let width = Theme.panelWidth
        // Never size to zero: a zero-area window never lays out, so it could never report its real height.
        let height = max(min(contentHeight, visible.height - 12), Self.minimumHeight)
        let x = min(max(buttonFrame.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
        let y = buttonFrame.minY - height - 6
        let frame = NSRect(x: x, y: y, width: width, height: height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            Log.ui.notice("Panel frame \(NSStringFromRect(frame), privacy: .public) (content height \(self.contentHeight, privacy: .public))")
        }
    }

    private func installMonitors() {
        removeMonitors()
        // Global monitors only see clicks delivered to other apps — exactly "clicked outside".
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Esc
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel.isKeyWindow else { return false }
                self.hidePanel(force: true)
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        outsideClickMonitor = nil
        keyMonitor = nil
    }
}
