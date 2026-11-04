import AppKit

/// Plain AppKit entry point: the app is a menu bar agent (LSUIElement) with no main window.
@main
enum SoundSourceMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
