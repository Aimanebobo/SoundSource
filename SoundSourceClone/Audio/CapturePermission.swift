import AppKit
import Foundation

/// "System Audio Recording" (kTCCServiceAudioCapture) permission, required for process taps on macOS 14.4+.
///
/// There is no public API to query it. Without it a tap delivers silence, and because taps here mute
/// the app at its source, starting one before access is granted would silence that app. So the state
/// is checked up front through the TCC SPI (loaded dynamically, the same way insidegui/AudioCap does).
enum CapturePermission {
    enum Status { case authorized, denied, unknown }

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private static let preflight: PreflightFunction? = {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: PreflightFunction.self)
    }()

    private static let requestAccess: RequestFunction? = {
        guard let handle, let symbol = dlsym(handle, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(symbol, to: RequestFunction.self)
    }()

    /// False when the SPI is unavailable; the first tap creation then shows the system prompt itself.
    static var canRequest: Bool { preflight != nil && requestAccess != nil }

    static var status: Status {
        guard let preflight else { return .unknown }
        switch preflight(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(_ completion: @escaping (Bool) -> Void) {
        guard let requestAccess else {
            completion(true)
            return
        }
        requestAccess(service, nil) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
