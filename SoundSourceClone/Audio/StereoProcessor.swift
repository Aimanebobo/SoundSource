import AudioToolbox
import Darwin

/// Gain, balance, 10-band EQ, soft clipping and peak metering for one captured app.
///
/// `render` runs on the HAL's real-time IO thread, so it never allocates, locks or touches Swift
/// collections. The main thread talks to it through preallocated raw memory: plain 32-bit loads and
/// stores for scalars, and a double-buffered coefficient bank for the EQ.
final class StereoProcessor {
    static let bandCount = EQBands.count
    private static let bandQ = 1.41
    private static let stateCount = 2 * bandCount * 2

    // 0: target gain, 1: left balance gain, 2: right balance gain, 3: peak L, 4: peak R
    private let shared = UnsafeMutablePointer<Float>.allocate(capacity: 5)
    // Two banks × bands × (b0 b1 b2 a1 a2)
    private let coefficients = UnsafeMutablePointer<Float>.allocate(capacity: 2 * StereoProcessor.bandCount * 5)
    // 0: active bank, 1: bank-0 band mask, 2: bank-1 band mask
    private let bankInfo = UnsafeMutablePointer<Int32>.allocate(capacity: 3)
    // Two channels × bands × two TDF-II state values
    private let filterState = UnsafeMutablePointer<Float>.allocate(capacity: StereoProcessor.stateCount)
    private let smoothing = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    /// Touched only on the IO thread. Starts at 0 so a new tap fades in instead of popping.
    private var renderGain: Float = 0
    private var eqGains = [Float](repeating: 0, count: StereoProcessor.bandCount)
    private(set) var sampleRate: Double = 48_000

    init() {
        shared.initialize(repeating: 0, count: 5)
        shared[0] = 1
        shared[1] = 1
        shared[2] = 1
        coefficients.initialize(repeating: 0, count: 2 * Self.bandCount * 5)
        bankInfo.initialize(repeating: 0, count: 3)
        filterState.initialize(repeating: 0, count: Self.stateCount)
        smoothing.initialize(to: 0.002)
    }

    deinit {
        shared.deallocate()
        coefficients.deallocate()
        bankInfo.deallocate()
        filterState.deallocate()
        smoothing.deallocate()
    }

    // MARK: Main-thread API

    func setGain(_ gain: Float) { shared[0] = max(gain, 0) }

    /// -1 (left) … +1 (right); the far side is attenuated linearly.
    func setBalance(_ balance: Float) {
        let value = min(max(balance, -1), 1)
        shared[1] = value > 0 ? 1 - value : 1
        shared[2] = value < 0 ? 1 + value : 1
    }

    func setEQ(gains: [Float]) {
        eqGains = gains
        rebuildCoefficients()
    }

    func prepare(sampleRate: Double) {
        guard sampleRate > 0 else { return }
        self.sampleRate = sampleRate
        smoothing.pointee = Float(1 - exp(-1 / (0.012 * sampleRate)))   // ~12 ms gain glide
        rebuildCoefficients()
    }

    /// Returns and clears the peaks accumulated since the last call.
    func takePeaks() -> (left: Float, right: Float) {
        let peaks = (left: shared[3], right: shared[4])
        shared[3] = 0
        shared[4] = 0
        return peaks
    }

    private func rebuildCoefficients() {
        let next = 1 - Int(bankInfo[0])
        let bank = coefficients + next * Self.bandCount * 5
        var mask: Int32 = 0
        for (band, frequency) in EQBands.frequencies.enumerated() {
            let gainDB = Double(band < eqGains.count ? eqGains[band] : 0)
            guard abs(gainDB) > 0.05, frequency < sampleRate * 0.45 else { continue }
            // RBJ cookbook peaking filter.
            let a = pow(10, gainDB / 40)
            let w0 = 2 * Double.pi * frequency / sampleRate
            let alpha = sin(w0) / (2 * Self.bandQ)
            let cosW0 = cos(w0)
            let a0 = 1 + alpha / a
            let c = bank + band * 5
            c[0] = Float((1 + alpha * a) / a0)
            c[1] = Float(-2 * cosW0 / a0)
            c[2] = Float((1 - alpha * a) / a0)
            c[3] = Float(-2 * cosW0 / a0)
            c[4] = Float((1 - alpha / a) / a0)
            mask |= 1 << Int32(band)
        }
        bankInfo[1 + next] = mask
        OSMemoryBarrier()   // publish the coefficients before flipping the bank
        bankInfo[0] = Int32(next)
    }

    // MARK: IO thread

    /// Reads the tap's stereo mix from `input` and writes the processed signal to `output`.
    /// The tap's channels are the last two input channels of the aggregate device (they follow any
    /// input channels the output sub-device contributes).
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let inputChannels = Self.channelCount(inputs)
        guard inputChannels > 0,
              let inL = Self.channel(inputs, max(inputChannels - 2, 0)),
              let inR = Self.channel(inputs, inputChannels - 1),
              let outL = Self.channel(outputs, 0) else { return }
        let outR = Self.channel(outputs, 1)
        var frames = min(inL.frames, inR.frames, outL.frames)
        if let outR { frames = min(frames, outR.frames) }
        guard frames > 0 else { return }

        let bank = Int(bankInfo[0])
        let mask = bankInfo[1 + bank]
        let coeffs = coefficients + bank * Self.bandCount * 5
        let target = shared[0]
        let balanceL = shared[1]
        let balanceR = shared[2]
        let k = smoothing.pointee
        var gain = renderGain
        var peakL: Float = 0
        var peakR: Float = 0

        for frame in 0..<frames {
            gain += (target - gain) * k
            var left = inL.data[frame * inL.stride]
            var right = inR.data[frame * inR.stride]
            if mask != 0 {
                left = runEQ(left, channel: 0, coeffs: coeffs, mask: mask)
                right = runEQ(right, channel: 1, coeffs: coeffs, mask: mask)
            }
            left = Self.softClip(left * gain * balanceL)
            right = Self.softClip(right * gain * balanceR)
            peakL = max(peakL, abs(left))
            peakR = max(peakR, abs(right))
            if let outR {
                outL.data[frame * outL.stride] = left
                outR.data[frame * outR.stride] = right
            } else {
                outL.data[frame * outL.stride] = 0.5 * (left + right)
            }
        }

        renderGain = gain
        if mask != 0 { sanitizeFilterState() }
        if peakL > shared[3] { shared[3] = peakL }
        if peakR > shared[4] { shared[4] = peakR }
    }

    @inline(__always)
    private func runEQ(_ x: Float, channel: Int, coeffs: UnsafeMutablePointer<Float>, mask: Int32) -> Float {
        var y = x
        let state = filterState + channel * Self.bandCount * 2
        var band = 0
        while band < Self.bandCount {
            if mask & (1 << Int32(band)) != 0 {
                let c = coeffs + band * 5
                let s = state + band * 2
                let out = c[0] * y + s[0]
                s[0] = c[1] * y - c[3] * out + s[1]
                s[1] = c[2] * y - c[4] * out
                y = out
            }
            band += 1
        }
        return y
    }

    /// Flushes denormals and recovers from any non-finite state.
    @inline(__always)
    private func sanitizeFilterState() {
        var i = 0
        while i < Self.stateCount {
            let value = filterState[i]
            if !value.isFinite || abs(value) < 1e-25 { filterState[i] = 0 }
            i += 1
        }
    }

    /// Transparent below 0.85, then a tanh knee that never exceeds ±1 (keeps 100 %+ boost clean).
    @inline(__always)
    private static func softClip(_ x: Float) -> Float {
        let magnitude = abs(x)
        guard magnitude > 0.85 else { return x }
        let shaped = 0.85 + 0.15 * tanhf((magnitude - 0.85) / 0.15)
        return x < 0 ? -shaped : shaped
    }

    private struct Channel {
        let data: UnsafeMutablePointer<Float>
        let stride: Int
        let frames: Int
    }

    @inline(__always)
    private static func channelCount(_ list: UnsafeMutableAudioBufferListPointer) -> Int {
        var total = 0
        for buffer in list { total += Int(buffer.mNumberChannels) }
        return total
    }

    /// Locates channel `index` across the (possibly interleaved, possibly multi-stream) buffer list.
    @inline(__always)
    private static func channel(_ list: UnsafeMutableAudioBufferListPointer, _ index: Int) -> Channel? {
        var first = 0
        for buffer in list {
            let count = Int(buffer.mNumberChannels)
            if index < first + count {
                guard let data = buffer.mData, count > 0 else { return nil }
                let frames = Int(buffer.mDataByteSize) / (count * MemoryLayout<Float>.size)
                return Channel(data: data.assumingMemoryBound(to: Float.self) + (index - first),
                               stride: count,
                               frames: frames)
            }
            first += count
        }
        return nil
    }
}
