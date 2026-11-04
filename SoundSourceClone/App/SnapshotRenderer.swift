import AppKit
import SwiftUI

/// Renders the panel with `PreviewData` to a PNG, without touching Core Audio.
@MainActor
enum SnapshotRenderer {
    static func render(to url: URL, expanded: Bool) {
        let engine = AudioEngine(preview: true)
        if expanded { engine.previewExpandedAppID = PreviewData.expandedAppID }
        let state = PanelState()
        state.isSnapshot = true

        let content = PopoverRootView()
            .environment(engine)
            .environment(state)
            .background(Theme.snapshotBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .padding(28)
            .background(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)],
                                       startPoint: .top, endPoint: .bottom))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        // On HDR displays ImageRenderer can produce a BT.2100 PQ image; flatten to 8-bit sRGB.
        guard let rendered = renderer.cgImage,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: rendered.width, height: rendered.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("Snapshot rendering failed")
            return
        }
        context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("Snapshot rendering failed")
            return
        }
        do {
            try data.write(to: url)
            print("Snapshot written to \(url.path)")
        } catch {
            print("Snapshot write failed: \(error.localizedDescription)")
        }
    }
}
