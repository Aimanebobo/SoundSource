import AppKit
import SwiftUI

/// Borderless, non-activating, dark translucent panel that hangs below the status item —
/// the same kind of overlay SoundSource uses instead of an `NSPopover`.
final class FloatingPanel: NSPanel {
    private let effectView = NSVisualEffectView()

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
        appearance = NSAppearance(named: .darkAqua)

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: Theme.cornerRadius)
        contentView = effectView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var hostingController: NSViewController?
    private var sizeObservation: NSKeyValueObservation?

    /// Called with SwiftUI's ideal content height whenever it changes.
    var onContentHeightChange: ((CGFloat) -> Void)?

    func setRootView<Content: View>(_ view: Content) {
        let controller = NSHostingController(rootView: view)
        // SwiftUI publishes its ideal size as preferredContentSize; the menu bar controller turns that
        // into a top-anchored window frame. The hosting view itself adds no size constraints.
        controller.sizingOptions = [.preferredContentSize]
        let hosting = controller.view
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        hostingController = controller
        sizeObservation = controller.observe(\.preferredContentSize, options: [.initial, .new]) { [weak self] controller, _ in
            let height = controller.preferredContentSize.height
            DispatchQueue.main.async { self?.onContentHeightChange?(height) }
        }
    }

    var contentHeight: CGFloat { hostingController?.preferredContentSize.height ?? 0 }

    /// Renders the live SwiftUI content to a PNG (for `--dump-panel`; no screen-recording permission needed).
    func writeContentImage(to url: URL) -> Bool {
        guard let view = hostingController?.view,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        // The blur isn't captured, so composite over a dark fill like the real panel's background.
        let image = NSImage(size: view.bounds.size, flipped: false) { rect in
            NSColor(white: 0.14, alpha: 1).setFill()
            rect.fill()
            rep.draw(in: rect)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// Stretchable rounded-rect mask: the reliable way to round an NSVisualEffectView's corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
