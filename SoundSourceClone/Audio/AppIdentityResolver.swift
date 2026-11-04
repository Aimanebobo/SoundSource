import AppKit
import Darwin

struct AppIdentity {
    let id: String
    let name: String
    let bundleID: String?
    let bundleURL: URL?
    let icon: NSImage
    /// A Dock app (not a menu bar agent or background helper).
    var isRegularApp = false
}

/// Maps audio processes to the app the user thinks of: Chrome's renderer/audio helpers become
/// "Google Chrome", Safari's WebKit GPU process becomes "Safari", and so on.
@MainActor
final class AppIdentityResolver {
    static let genericIcon = NSWorkspace.shared.icon(for: .application)

    /// Per-app audio engines, including every copy of this app (another build, an Xcode run).
    /// Tapping one would fight its interception; two copies tapping each other form a feedback loop.
    private static let excludedBundleIDs: Set<String> = [
        "com.rogueamoeba.arkaudiod",
        Bundle.main.bundleIdentifier ?? "com.example.SoundSourceClone",
    ]

    private var cache: [pid_t: AppIdentity] = [:]
    private let ownPID = getpid()

    func identity(for process: AudioProcess) -> AppIdentity? {
        if let cached = cache[process.pid] { return cached }
        // Negative results are not cached: a just-launched app may not be registered with LaunchServices yet.
        guard let resolved = resolve(process) else { return nil }
        cache[process.pid] = resolved
        return resolved
    }

    func retain(pids: Set<pid_t>) {
        cache = cache.filter { pids.contains($0.key) }
    }

    private func resolve(_ process: AudioProcess) -> AppIdentity? {
        guard process.pid != ownPID, !Self.excludedBundleIDs.contains(process.bundleID ?? "") else { return nil }
        let responsible = Self.responsiblePID(for: process.pid)
        guard responsible != ownPID else { return nil }

        for pid in [responsible, process.pid] {
            if let app = NSRunningApplication(processIdentifier: pid),
               app.activationPolicy != .prohibited,
               let bundleID = app.bundleIdentifier,
               !Self.excludedBundleIDs.contains(bundleID) {
                return AppIdentity(id: bundleID,
                                   name: Self.cleanName(app.localizedName) ?? bundleID,
                                   bundleID: bundleID,
                                   bundleURL: app.bundleURL,
                                   icon: app.icon ?? Self.genericIcon,
                                   isRegularApp: app.activationPolicy == .regular)
            }
        }

        // Helpers that are not registered apps: use the outermost .app bundle around the executable.
        guard let appURL = Self.outermostAppBundle(for: process.pid),
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier,
              !Self.excludedBundleIDs.contains(bundleID) else { return nil }
        let name = Self.cleanName(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? Self.cleanName(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        return AppIdentity(id: bundleID, name: name, bundleID: bundleID, bundleURL: appURL,
                           icon: NSWorkspace.shared.icon(forFile: appURL.path))
    }

    /// Some apps (WhatsApp) prefix their name with a left-to-right mark.
    private static func cleanName(_ name: String?) -> String? {
        let invisible = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202C}"))
        guard let cleaned = name?.trimmingCharacters(in: invisible), !cleaned.isEmpty else { return nil }
        return cleaned
    }

    // `responsibility_get_pid_responsible_for_pid` is the SPI TCC uses to attribute helpers and
    // XPC services to their host app. Looked up dynamically so a missing symbol only disables grouping.
    private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t
    private static let responsibilityFunction: ResponsibilityFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibilityFunction.self)
    }()

    static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let function = responsibilityFunction else { return pid }
        let responsible = function(pid)
        return responsible > 0 ? responsible : pid
    }

    private static func outermostAppBundle(for pid: pid_t) -> URL? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        guard !path.hasPrefix("/System/Library/"), !path.hasPrefix("/usr/"),
              let range = path.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(path[..<range.upperBound].dropLast()))
    }
}
