import Foundation

/// The alert ("sound effects") volume has no public Core Audio property. Standard Additions'
/// `volume settings` runs in-process, so it needs no Apple Events permission.
@MainActor
enum AlertVolume {
    static func read() -> Float? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: "alert volume of (get volume settings)") else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return Float(result.int32Value) / 100
    }

    static func write(_ value: Float) {
        let percent = Int((min(max(value, 0), 1) * 100).rounded())
        var error: NSDictionary?
        NSAppleScript(source: "set volume alert volume \(percent)")?.executeAndReturnError(&error)
        if let error { NSLog("SoundSourceClone: alert volume write failed: \(error)") }
    }
}
