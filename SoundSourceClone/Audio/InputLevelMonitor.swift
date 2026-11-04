import AVFoundation

/// Optional microphone meter. Opening the input lights the system's mic-in-use indicator, so the
/// engine only runs this while the panel is visible and the user has enabled it in Settings.
final class InputLevelMonitor {
    private let engine = AVAudioEngine()
    private let peak = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var configurationObserver: NSObjectProtocol?
    private var isRunning = false

    init() { peak.initialize(to: 0) }

    deinit {
        stop()
        peak.deallocate()
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning, AVCaptureDevice.authorizationStatus(for: .audio) != .denied else { return isRunning }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return false }
        let peak = self.peak
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            var loudest: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(samples[frame])) }
            }
            if loudest > peak.pointee { peak.pointee = loudest }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        isRunning = true
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // The default input device changed: rebuild the tap with the new format.
            self?.stop()
            self?.start()
        }
        return true
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    func takePeak() -> Float {
        let value = peak.pointee
        peak.pointee = 0
        return value
    }
}
