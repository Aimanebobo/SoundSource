// Draws the SoundSource Clone app icon (three mixer sliders on a purple-to-blue squircle) and
// writes every macOS AppIcon size, each rendered from the vector drawing at its own resolution.
//
//   swift Scripts/make-icon.swift SoundSourceClone/Assets.xcassets/AppIcon.appiconset [docs/logo.png]
//
// Drawn with plain Core Graphics paths: Apple's SF Symbols license doesn't allow symbols in app icons.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: swift make-icon.swift <AppIcon.appiconset> [logo.png]")
    exit(64)
}
let iconSetURL = URL(fileURLWithPath: arguments[1])
let logoURL = arguments.count > 2 ? URL(fileURLWithPath: arguments[2]) : nil
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

/// The whole design on a 1024 × 1024 canvas (origin bottom-left), following Apple's macOS icon grid:
/// an 824 pt squircle inset 100 pt, with a soft shadow below it.
func drawIcon(in context: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
    context.addPath(bodyPath)
    context.setFillColor(color(0.30, 0.38, 1.0))
    context.fillPath()
    context.restoreGState()

    // Background: violet at the top to blue at the bottom, with a soft highlight near the top edge.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let background = CGGradient(colorsSpace: sRGB,
                                colors: [color(0.56, 0.36, 1.0), color(0.36, 0.40, 1.0), color(0.13, 0.47, 1.0)] as CFArray,
                                locations: [0, 0.5, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glow = CGGradient(colorsSpace: sRGB,
                          colors: [color(1, 1, 1, 0.28), color(1, 1, 1, 0)] as CFArray,
                          locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 900), endRadius: 560, options: [])
    context.restoreGState()

    // Hairline edge so the icon holds its shape on dark backgrounds.
    context.saveGState()
    context.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    context.setStrokeColor(color(1, 1, 1, 0.18))
    context.setLineWidth(4)
    context.strokePath()
    context.restoreGState()

    // Three mixer channels: track, level fill below the knob, knob with a coloured centre.
    let trackBottom: CGFloat = 260
    let trackTop: CGFloat = 764
    let trackWidth: CGFloat = 46
    let channels: [(x: CGFloat, knob: CGFloat)] = [(352, 400), (512, 650), (672, 520)]
    for channel in channels {
        let track = CGRect(x: channel.x - trackWidth / 2, y: trackBottom, width: trackWidth, height: trackTop - trackBottom)
        context.addPath(CGPath(roundedRect: track, cornerWidth: trackWidth / 2, cornerHeight: trackWidth / 2, transform: nil))
        context.setFillColor(color(1, 1, 1, 0.24))
        context.fillPath()

        let level = CGRect(x: track.minX, y: trackBottom, width: trackWidth, height: channel.knob - trackBottom)
        context.addPath(CGPath(roundedRect: level, cornerWidth: trackWidth / 2, cornerHeight: trackWidth / 2, transform: nil))
        context.setFillColor(color(1, 1, 1, 0.92))
        context.fillPath()

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0.05, 0.05, 0.25, 0.40))
        context.addEllipse(in: CGRect(x: channel.x - 66, y: channel.knob - 66, width: 132, height: 132))
        context.setFillColor(color(1, 1, 1))
        context.fillPath()
        context.restoreGState()

        context.addEllipse(in: CGRect(x: channel.x - 24, y: channel.knob - 24, width: 48, height: 48))
        context.setFillColor(color(0.33, 0.42, 1.0))
        context.fillPath()
    }
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    drawIcon(in: context)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        writePNG(render(pixels: size * scale), to: iconSetURL.appendingPathComponent(name))
        entries.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try (json + Data("\n".utf8)).write(to: iconSetURL.appendingPathComponent("Contents.json"))

if let logoURL {
    try FileManager.default.createDirectory(at: logoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    writePNG(render(pixels: 1024), to: logoURL)
}
print("Wrote \(entries.count) icon sizes to \(iconSetURL.path)")
