import AppKit
import SwiftUI

struct BottomBarView: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        HStack(spacing: 8) {
            PopUpMenuButton(items: favoriteItems) {
                CapsuleLabel(title: "Add Favorite", symbol: "plus", showsChevron: true)
            }
            .help("Keep an app in the list, even when it isn't running")
            Spacer()
            PopUpMenuButton(items: quickConfigItems) {
                CapsuleLabel(title: "Quick Configs", symbol: "rectangle.stack", showsChevron: true)
            }
            .help("Save and restore sets of volumes, effects and routes")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private func favoriteItems() -> [MenuItemSpec] {
        var items: [MenuItemSpec] = [.header("Running Applications")]
        let candidates = engine.favoriteCandidates()
        if candidates.isEmpty { items.append(.note("No other running apps")) }
        items += candidates.map { app in
            .action(app.localizedName ?? app.bundleIdentifier ?? "App", image: app.icon?.resized(to: 16)) {
                engine.addFavorite(app)
            }
        }
        items += [
            .separator,
            .action("Choose Application…", symbol: "folder") { engine.chooseFavoriteFromDisk() },
        ]
        return items
    }

    private func quickConfigItems() -> [MenuItemSpec] {
        var items: [MenuItemSpec] = []
        if engine.quickConfigs.isEmpty {
            items.append(.note("No saved configurations"))
        } else {
            items.append(.header("Apply"))
            items += engine.quickConfigs.map { config in
                .action(config.name, symbol: "rectangle.stack") { engine.applyQuickConfig(config) }
            }
        }
        items += [
            .separator,
            .action("Save Current Configuration…", symbol: "square.and.arrow.down") {
                let suggestion = "Config \(engine.quickConfigs.count + 1)"
                if let name = TextPrompt.run(title: "Save Quick Config",
                                             message: "Saves app volumes, effects and routes plus the current system devices.",
                                             defaultValue: suggestion,
                                             confirmTitle: "Save") {
                    engine.saveQuickConfig(named: name)
                }
            },
            .submenu("Delete", symbol: "trash", engine.quickConfigs.map { config in
                .action(config.name) { engine.deleteQuickConfig(config) }
            }),
        ]
        return items
    }
}

@MainActor
enum TextPrompt {
    static func run(title: String, message: String, defaultValue: String, confirmTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        NSApp.activate()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
