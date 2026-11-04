import AppKit
import SwiftUI

/// Declarative description of an NSMenu, so SwiftUI views can pop real menus with custom-styled buttons.
struct MenuItemSpec {
    enum Kind {
        case action(() -> Void)
        case header
        case separator
        case submenu([MenuItemSpec])
    }

    var title = ""
    var image: NSImage?
    var isChecked = false
    var isEnabled = true
    var kind: Kind

    static var separator: MenuItemSpec { MenuItemSpec(kind: .separator) }

    static func header(_ title: String) -> MenuItemSpec { MenuItemSpec(title: title, kind: .header) }

    static func note(_ title: String, symbol: String? = nil) -> MenuItemSpec {
        MenuItemSpec(title: title, image: symbol.flatMap(NSImage.menuSymbol), isEnabled: false, kind: .action {})
    }

    static func action(_ title: String,
                       image: NSImage? = nil,
                       symbol: String? = nil,
                       checked: Bool = false,
                       enabled: Bool = true,
                       _ handler: @escaping () -> Void) -> MenuItemSpec {
        MenuItemSpec(title: title, image: image ?? symbol.flatMap(NSImage.menuSymbol),
                     isChecked: checked, isEnabled: enabled, kind: .action(handler))
    }

    static func submenu(_ title: String, symbol: String? = nil, _ items: [MenuItemSpec]) -> MenuItemSpec {
        MenuItemSpec(title: title, image: symbol.flatMap(NSImage.menuSymbol), isEnabled: !items.isEmpty, kind: .submenu(items))
    }
}

@MainActor
enum MenuBuilder {
    static func menu(_ items: [MenuItemSpec]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: .darkAqua)
        for spec in items { menu.addItem(item(spec)) }
        return menu
    }

    /// Pops `menu` with its top-left corner just below `view`.
    static func popUp(_ menu: NSMenu, below view: NSView) {
        let y: CGFloat = view.isFlipped ? view.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
    }

    private static func item(_ spec: MenuItemSpec) -> NSMenuItem {
        let item: NSMenuItem
        switch spec.kind {
        case .separator:
            return .separator()
        case .header:
            return .sectionHeader(title: spec.title)
        case .action(let handler):
            item = ClosureMenuItem(title: spec.title, handler: handler)
        case .submenu(let children):
            item = NSMenuItem(title: spec.title, action: nil, keyEquivalent: "")
            item.submenu = menu(children)
        }
        item.image = spec.image
        item.state = spec.isChecked ? .on : .off
        item.isEnabled = spec.isEnabled
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

extension NSImage {
    static func menuSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    func resized(to side: CGFloat) -> NSImage {
        let copy = (self.copy() as? NSImage) ?? self
        copy.size = NSSize(width: side, height: side)
        return copy
    }
}

/// A SwiftUI button with a fully custom label that pops an NSMenu anchored to itself.
struct PopUpMenuButton<Label: View>: View {
    private let items: () -> [MenuItemSpec]
    private let label: Label
    @Environment(PanelState.self) private var panel
    @State private var anchor = MenuAnchor.Box()

    init(items: @escaping () -> [MenuItemSpec], @ViewBuilder label: () -> Label) {
        self.items = items
        self.label = label()
    }

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            MenuBuilder.popUp(MenuBuilder.menu(items()), below: view)
        } label: {
            label
        }
        .buttonStyle(.plain)
        .background {
            // ImageRenderer draws placeholders for AppKit views, so snapshots skip the anchor.
            if !panel.isSnapshot { MenuAnchor(box: anchor) }
        }
    }
}

/// An invisible NSView that gives the menu a position in window coordinates.
struct MenuAnchor: NSViewRepresentable {
    final class Box {
        weak var view: NSView?
    }

    let box: Box

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}
