import AppKit
import CoreAudio
import Observation
import UniformTypeIdentifiers

/// Owns the app list and one `ProcessTapSession` per captured app, and turns user settings into
/// processor parameters. Everything here runs on the main thread; only `StereoProcessor.render`
/// runs on the audio IO threads.
@MainActor @Observable
final class AudioEngine {
    let devices: AudioDeviceManager
    let isPreview: Bool

    private(set) var apps: [AppEntry] = []
    private(set) var favorites: [FavoriteApp]
    private(set) var quickConfigs: [QuickConfig]
    private(set) var permission: CapturePermission.Status = .unknown
    /// Loudest captured app, 0…1 (used as the System Output meter).
    private(set) var outputLevel: Float = 0
    private(set) var inputLevel: Float = 0

    var prefs: Preferences {
        didSet { preferencesChanged(from: oldValue) }
    }

    /// Applied to every captured app, on top of its own EQ.
    var systemEQ: EQSettings {
        didSet {
            applyProcessingToAll()
            if systemEQ.isActive != oldValue.isActive { syncSessions() }
            persist()
        }
    }

    @ObservationIgnored var previewExpandedAppID: String?
    @ObservationIgnored private var appSettings: [String: AppAudioSettings]
    @ObservationIgnored private var entries: [String: AppEntry] = [:]
    @ObservationIgnored private var sessions: [String: ProcessTapSession] = [:]
    @ObservationIgnored private var failedStarts: [String: String] = [:]
    @ObservationIgnored private var heardThisSession: Set<String> = []
    private let processMonitor = AudioProcessMonitor()
    private let identities = AppIdentityResolver()
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var levelLogTimer: Timer?
    @ObservationIgnored private var inputMonitor: InputLevelMonitor?
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored private var refreshScheduled = false
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []

    init(preview: Bool = false) {
        isPreview = preview
        let state = preview ? PreviewData.state : PersistedState.load()
        devices = AudioDeviceManager(preview: preview)
        appSettings = state.apps
        favorites = state.favorites
        quickConfigs = state.quickConfigs
        prefs = state.prefs
        systemEQ = state.systemEQ
        if preview {
            permission = .authorized
            loadPreviewApps()
        }
    }

    // MARK: Lifecycle

    func start() {
        guard !isPreview else { return }
        devices.onChange = { [weak self] change in self?.deviceConfigurationChanged(change) }
        devices.start()
        processMonitor.onChange = { [weak self] in self?.scheduleRefresh() }
        processMonitor.start()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }

        permission = CapturePermission.status
        Log.capture.notice("Started. System Audio Recording permission: \(String(describing: self.permission), privacy: .public)")
        if permission == .unknown, CapturePermission.canRequest {
            requestCapturePermission()
        }
        if CommandLine.arguments.contains("--log-levels") {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.logLevels() }
            }
            RunLoop.main.add(timer, forMode: .common)
            levelLogTimer = timer
        }
        refreshApps()
    }

    /// `--log-levels`: periodic per-app peak levels in the unified log (only while the panel is closed,
    /// since the panel's meters consume the same peaks).
    private func logLevels() {
        guard meterTimer == nil else { return }
        for (id, session) in sessions {
            let peaks = session.processor.takePeaks()
            let db = 20 * log10f(max(peaks.left, peaks.right, 0.000_001))
            Log.capture.notice("Level \(self.entries[id]?.name ?? id, privacy: .public): \(String(format: "%.1f", db), privacy: .public) dBFS peak")
        }
    }

    func shutdown() {
        for session in sessions.values { session.stop() }
        sessions.removeAll()
        saveWorkItem?.cancel()
        persistNow()
    }

    // MARK: Permission

    var canCapture: Bool {
        switch permission {
        case .authorized: true
        case .denied: false
        case .unknown: !CapturePermission.canRequest   // no SPI: let tap creation show the prompt
        }
    }

    func requestCapturePermission() {
        if permission == .denied {
            CapturePermission.openSystemSettings()
            return
        }
        CapturePermission.request { [weak self] granted in
            guard let self else { return }
            Log.capture.notice("System Audio Recording permission \(granted ? "granted" : "denied", privacy: .public)")
            self.permission = granted ? .authorized : .denied
            self.failedStarts.removeAll()
            self.syncSessions()
        }
    }

    /// The user may have granted access in System Settings since the last check.
    func recheckPermission() {
        guard !isPreview, CapturePermission.canRequest else { return }
        let status = CapturePermission.status
        if status != permission {
            permission = status
            failedStarts.removeAll()
            syncSessions()
        }
    }

    // MARK: App list

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshScheduled = false
                self?.refreshApps()
            }
        }
    }

    private func refreshApps() {
        guard !isPreview else { return rebuildList() }

        var groups: [String: (identity: AppIdentity, processes: [AudioProcess])] = [:]
        for process in processMonitor.processes {
            guard let identity = identities.identity(for: process) else { continue }
            groups[identity.id, default: (identity, [])].processes.append(process)
        }
        identities.retain(pids: Set(processMonitor.processes.map(\.pid)))

        for (id, group) in groups {
            let identity = group.identity
            let entry = entries[id] ?? makeEntry(id: id, name: identity.name, icon: identity.icon,
                                                 bundleID: identity.bundleID, bundleURL: identity.bundleURL)
            let objectIDs = group.processes.map(\.objectID).sorted()
            if entry.processObjectIDs != objectIDs { entry.processObjectIDs = objectIDs }
            entry.pids = Array(Set(group.processes.map(\.pid))).sorted()
            entry.isRegularApp = identity.isRegularApp
            entry.isRunning = true
            entry.isPlaying = group.processes.contains(where: \.isRunningOutput)
            let native = group.processes.filter(\.isRunningOutput).flatMap(\.outputDeviceIDs).first
                ?? group.processes.flatMap(\.outputDeviceIDs).first
            if entry.nativeOutputDeviceID != native { entry.nativeOutputDeviceID = native }
            if entry.isPlaying { heardThisSession.insert(id) }
        }

        for (id, entry) in entries where groups[id] == nil {
            entry.processObjectIDs = []
            entry.pids = []
            entry.nativeOutputDeviceID = nil
            entry.isPlaying = false
            entry.level = 0
            entry.isRunning = entry.bundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
            if !entry.isRunning { heardThisSession.remove(id) }
        }

        for favorite in favorites where entries[favorite.id] == nil {
            let url = favorite.bundlePath.map { URL(fileURLWithPath: $0) }
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: favorite.id)
            let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? AppIdentityResolver.genericIcon
            let entry = makeEntry(id: favorite.id, name: favorite.name, icon: icon, bundleID: favorite.id, bundleURL: url)
            entry.isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: favorite.id).isEmpty
        }

        rebuildList()
        syncSessions()
    }

    private func makeEntry(id: String, name: String, icon: NSImage, bundleID: String?, bundleURL: URL?) -> AppEntry {
        let entry = AppEntry(id: id, name: name, icon: icon, bundleID: bundleID, bundleURL: bundleURL,
                             settings: appSettings[id] ?? AppAudioSettings())
        entries[id] = entry
        return entry
    }

    /// Favorites first (in the order they were added), then apps that played audio this session or
    /// are Dock apps with an open audio connection (shown dimmed until they play, so they can be
    /// adjusted ahead of time; capture still waits for sound or a change).
    private func rebuildList() {
        let favoriteIDs = favorites.map(\.id)
        let favoriteSet = Set(favoriteIDs)
        for entry in entries.values where entry.isFavorite != favoriteSet.contains(entry.id) {
            entry.isFavorite.toggle()
        }
        let pinned = favoriteIDs.compactMap { entries[$0] }
        let others = entries.values
            .filter { entry in
                !favoriteSet.contains(entry.id)
                    && (entry.isPlaying || heardThisSession.contains(entry.id)
                        || ((entry.settings.isAdjusted || entry.isRegularApp) && !entry.processObjectIDs.isEmpty))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let list = pinned + others
        if list.map(\.id) != apps.map(\.id) { apps = list }
    }

    // MARK: Capture sessions

    private func shouldCapture(_ entry: AppEntry) -> Bool {
        guard canCapture, !entry.processObjectIDs.isEmpty else { return false }
        switch prefs.captureMode {
        case .allActive:
            return heardThisSession.contains(entry.id) || entry.settings.isAdjusted
        case .adjustedOnly:
            return entry.settings.isAdjusted || (systemEQ.isActive && heardThisSession.contains(entry.id))
        }
    }

    /// Explicit route if set and connected; otherwise wherever the app itself is playing, so capturing
    /// an app that chose its own device (a call app on a headset) doesn't move it to the default output.
    func outputDevice(for entry: AppEntry) -> AudioDevice? {
        if let uid = entry.settings.outputDeviceUID, let device = devices.device(uid: uid), device.hasOutput {
            return device
        }
        if let native = entry.nativeOutputDeviceID, let device = devices.device(id: native), device.hasOutput {
            return device
        }
        return devices.defaultOutput
    }

    private func syncSessions() {
        guard !isPreview else { return }
        var wanted = Set<String>()
        for entry in entries.values where shouldCapture(entry) {
            guard let output = outputDevice(for: entry) else { continue }
            let signature = "\(entry.processObjectIDs)|\(output.uid)"
            if let session = sessions[entry.id] {
                wanted.insert(entry.id)
                do {
                    if session.processObjectIDs != entry.processObjectIDs {
                        do {
                            try session.updateProcesses(entry.processObjectIDs)
                        } catch {
                            try session.start(processes: entry.processObjectIDs, output: output)
                        }
                    }
                    if session.outputDeviceUID != output.uid {
                        try session.switchOutput(to: output)
                        Log.capture.notice("Rerouted \(entry.name, privacy: .public) → \(output.name, privacy: .public)")
                    }
                    entry.captureError = nil
                } catch {
                    record(error, for: entry, signature: signature)
                    session.stop()
                    sessions[entry.id] = nil
                    wanted.remove(entry.id)
                }
            } else if failedStarts[entry.id] != signature {
                let session = ProcessTapSession(appID: entry.id)
                applyProcessing(entry, to: session.processor)
                do {
                    try session.start(processes: entry.processObjectIDs, output: output)
                    sessions[entry.id] = session
                    failedStarts[entry.id] = nil
                    entry.captureError = nil
                    wanted.insert(entry.id)
                    Log.capture.notice("Capturing \(entry.name, privacy: .public) (\(entry.processObjectIDs.count) processes) → \(output.name, privacy: .public) [\(session.formatSummary, privacy: .public)]")
                } catch {
                    record(error, for: entry, signature: signature)
                }
            }
            entry.isCaptured = sessions[entry.id]?.isRunning ?? false
        }

        for (id, session) in sessions where !wanted.contains(id) {
            Log.capture.notice("Stopped capturing \(self.entries[id]?.name ?? id, privacy: .public)")
            session.stop()
            sessions[id] = nil
            entries[id]?.isCaptured = false
            entries[id]?.level = 0
        }
    }

    private func record(_ error: Error, for entry: AppEntry, signature: String) {
        failedStarts[entry.id] = signature   // don't retry the same configuration in a loop
        entry.captureError = error.localizedDescription
        entry.isCaptured = false
        Log.capture.error("Capturing \(entry.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }

    private func deviceConfigurationChanged(_ change: AudioDeviceManager.Change) {
        switch change {
        case .deviceList, .defaultOutput:
            failedStarts.removeAll()
            syncSessions()   // re-resolves "follow system output" and disconnected routes
        case .defaultInput, .systemOutput:
            break
        }
    }

    // MARK: Processing parameters

    /// Squared taper: 50 % ≈ −12 dB, 200 % ≈ +12 dB.
    nonisolated static func gain(forVolume volume: Float) -> Float {
        let clamped = max(volume, 0)
        return clamped * clamped
    }

    nonisolated static func meterPosition(_ peak: Float) -> Float {
        guard peak > 0.000_01 else { return 0 }
        return min(max((20 * log10f(peak) + 60) / 60, 0), 1)
    }

    private func applyProcessing(_ entry: AppEntry, to processor: StereoProcessor) {
        let settings = entry.settings
        processor.setGain(settings.isMuted ? 0 : Self.gain(forVolume: settings.volume))
        processor.setBalance(settings.balance)
        var gains = [Float](repeating: 0, count: EQBands.count)
        for band in gains.indices {
            if settings.eq.enabled, band < settings.eq.gains.count { gains[band] += settings.eq.gains[band] }
            if systemEQ.enabled, band < systemEQ.gains.count { gains[band] += systemEQ.gains[band] }
        }
        processor.setEQ(gains: gains.map { min(max($0, -24), 24) })
    }

    private func applyProcessingToAll() {
        for (id, session) in sessions {
            if let entry = entries[id] { applyProcessing(entry, to: session.processor) }
        }
    }

    // MARK: Per-app settings

    func setVolume(_ volume: Float, for entry: AppEntry) {
        update(entry) {
            $0.volume = min(max(volume, 0), 2)
            if volume > 0 { $0.isMuted = false }
        }
    }

    func toggleMute(_ entry: AppEntry) { update(entry) { $0.isMuted.toggle() } }

    func setBalance(_ balance: Float, for entry: AppEntry) { update(entry) { $0.balance = balance } }

    func setEQ(_ eq: EQSettings, for entry: AppEntry) { update(entry) { $0.eq = eq } }

    func setOutputDevice(_ device: AudioDevice?, for entry: AppEntry) {
        update(entry) {
            $0.outputDeviceUID = device?.uid
            $0.outputDeviceName = device?.name
        }
    }

    func reset(_ entry: AppEntry) { update(entry) { $0 = AppAudioSettings() } }

    func resetAllApps() {
        for entry in entries.values { reset(entry) }
        appSettings.removeAll()
        persist()
    }

    private func update(_ entry: AppEntry, _ change: (inout AppAudioSettings) -> Void) {
        let old = entry.settings
        var new = old
        change(&new)
        guard new != old else { return }
        entry.settings = new
        appSettings[entry.id] = new.isAdjusted ? new : nil
        if let session = sessions[entry.id] { applyProcessing(entry, to: session.processor) }
        if new.outputDeviceUID != old.outputDeviceUID || new.isAdjusted != old.isAdjusted {
            failedStarts[entry.id] = nil
            syncSessions()
            rebuildList()
        }
        persist()
    }

    // MARK: Favorites

    func toggleFavorite(_ entry: AppEntry) {
        if let index = favorites.firstIndex(where: { $0.id == entry.id }) {
            favorites.remove(at: index)
        } else {
            favorites.append(FavoriteApp(id: entry.id, name: entry.name, bundlePath: entry.bundleURL?.path))
        }
        refreshApps()
        persist()
    }

    func addFavorite(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, !favorites.contains(where: { $0.id == id }) else { return }
        favorites.append(FavoriteApp(id: id, name: app.localizedName ?? id, bundlePath: app.bundleURL?.path))
        refreshApps()
        persist()
    }

    func addFavorite(bundleURL: URL) {
        guard let bundle = Bundle(url: bundleURL), let id = bundle.bundleIdentifier,
              !favorites.contains(where: { $0.id == id }) else { return }
        let name = FileManager.default.displayName(atPath: bundleURL.path)
            .replacingOccurrences(of: ".app", with: "")
        favorites.append(FavoriteApp(id: id, name: name, bundlePath: bundleURL.path))
        refreshApps()
        persist()
    }

    /// Regular running apps that are not favorites yet, for the "Add Favorite" menu.
    func favoriteCandidates() -> [NSRunningApplication] {
        let favoriteIDs = Set(favorites.map(\.id))
        let ownPID = getpid()
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, app.processIdentifier != ownPID,
                      let id = app.bundleIdentifier else { return false }
                return !favoriteIDs.contains(id)
            }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    func chooseFavoriteFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add Favorite"
        panel.message = "Choose apps to keep in the Applications list, even when they're not running."
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(addFavorite(bundleURL:))
    }

    // MARK: Quick Configs

    func saveQuickConfig(named name: String) {
        var snapshot = appSettings
        for entry in apps { snapshot[entry.id] = entry.settings }
        let config = QuickConfig(name: name,
                                 apps: snapshot,
                                 outputDeviceUID: devices.defaultOutput?.uid,
                                 inputDeviceUID: devices.defaultInput?.uid,
                                 soundEffectsDeviceUID: devices.systemOutput?.uid,
                                 outputVolume: devices.outputVolume,
                                 inputVolume: devices.inputVolume,
                                 systemEQ: systemEQ)
        quickConfigs.removeAll { $0.name == name }
        quickConfigs.append(config)
        persist()
    }

    func applyQuickConfig(_ config: QuickConfig) {
        if let uid = config.outputDeviceUID, let device = devices.device(uid: uid) { devices.setDefaultOutput(device) }
        if let uid = config.inputDeviceUID, let device = devices.device(uid: uid) { devices.setDefaultInput(device) }
        if let uid = config.soundEffectsDeviceUID, let device = devices.device(uid: uid) { devices.setSoundEffectsOutput(device) }
        if let volume = config.outputVolume { devices.setOutputVolume(volume) }
        if let volume = config.inputVolume { devices.setInputVolume(volume) }
        if let eq = config.systemEQ { systemEQ = eq }
        for (id, settings) in config.apps {
            if let entry = entries[id] {
                update(entry) { $0 = settings }
            } else {
                appSettings[id] = settings.isAdjusted ? settings : nil
            }
        }
        persist()
    }

    func deleteQuickConfig(_ config: QuickConfig) {
        quickConfigs.removeAll { $0.id == config.id }
        persist()
    }

    // MARK: Metering (runs only while the panel is visible)

    func beginMetering() {
        guard meterTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMeters() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
        updateInputMonitor()
    }

    func endMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        for entry in apps where entry.level != 0 { entry.level = 0 }
        outputLevel = 0
        inputLevel = 0
        updateInputMonitor()
    }

    private func updateMeters() {
        let decay: Float = 0.035
        var loudest: Float = 0
        for (id, session) in sessions {
            guard let entry = entries[id] else { continue }
            let peaks = session.processor.takePeaks()
            let level = max(Self.meterPosition(max(peaks.left, peaks.right)), entry.level - decay, 0)
            if abs(level - entry.level) > 0.002 { entry.level = level }
            loudest = max(loudest, level)
        }
        if abs(loudest - outputLevel) > 0.002 { outputLevel = loudest }
        if let inputMonitor {
            let level = max(Self.meterPosition(inputMonitor.takePeak()), inputLevel - decay, 0)
            if abs(level - inputLevel) > 0.002 { inputLevel = level }
        }
    }

    private func updateInputMonitor() {
        let wanted = !isPreview && prefs.showInputLevel && meterTimer != nil
        if wanted, inputMonitor == nil {
            let monitor = InputLevelMonitor()
            if monitor.start() { inputMonitor = monitor }
        } else if !wanted, let monitor = inputMonitor {
            monitor.stop()
            inputMonitor = nil
            inputLevel = 0
        }
    }

    // MARK: Persistence

    private func preferencesChanged(from old: Preferences) {
        if prefs.captureMode != old.captureMode { syncSessions() }
        if prefs.showInputLevel != old.showInputLevel { updateInputMonitor() }
        persist()
    }

    private func persist() {
        guard !isPreview else { return }
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.persistNow() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func persistNow() {
        guard !isPreview else { return }
        PersistedState(apps: appSettings, favorites: favorites, quickConfigs: quickConfigs,
                       systemEQ: systemEQ, prefs: prefs).save()
    }

    // MARK: Preview

    private func loadPreviewApps() {
        for app in PreviewData.apps {
            var settings = AppAudioSettings()
            settings.volume = app.volume
            settings.isMuted = app.muted
            if let gains = app.eq {
                settings.eq = EQSettings(enabled: true, gains: gains, presetName: EQPreset.matching(gains)?.name)
            }
            if let uid = app.outputUID {
                settings.outputDeviceUID = uid
                settings.outputDeviceName = devices.device(uid: uid)?.name
            }
            let entry = makeEntry(id: app.id, name: app.name, icon: PreviewData.icon(for: app),
                                  bundleID: app.id, bundleURL: nil)
            entry.settings = settings
            entry.isRunning = app.running
            entry.isPlaying = app.playing
            entry.isCaptured = app.playing
            entry.level = app.level
            entry.pids = app.running ? [Int32(400 + app.name.count * 37)] : []
            if app.playing { heardThisSession.insert(app.id) }
        }
        outputLevel = PreviewData.apps.map(\.level).max() ?? 0
        rebuildList()
    }
}
