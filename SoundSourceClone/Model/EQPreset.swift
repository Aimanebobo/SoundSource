import Foundation

enum EQBands {
    static let count = 10
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    static let labels = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    static let range: ClosedRange<Float> = -12...12
}

struct EQPreset: Identifiable {
    let name: String
    let gains: [Float]
    var id: String { name }

    static let all: [EQPreset] = [
        EQPreset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bass Boost", gains: [6, 5, 4, 2, 0.5, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bass Reducer", gains: [-6, -5, -4, -2, -0.5, 0, 0, 0, 0, 0]),
        EQPreset(name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        EQPreset(name: "Treble Reducer", gains: [0, 0, 0, 0, 0, -1, -2, -4, -5, -6]),
        EQPreset(name: "Vocal Boost", gains: [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
        EQPreset(name: "Spoken Word", gains: [-4, -3, 0, 1, 3, 4, 4, 3, 1, -2]),
        EQPreset(name: "Loudness", gains: [6, 4, 0, 0, -2, 0, -1, -1, 4, 2]),
        EQPreset(name: "Electronic", gains: [4, 3.5, 1, 0, -2, 2, 1, 1.5, 4, 5]),
        EQPreset(name: "Rock", gains: [5, 4, 3, 1, -1, -1, 1, 2.5, 3.5, 4.5]),
        EQPreset(name: "Acoustic", gains: [4.5, 4.5, 3.5, 1, 2, 1.5, 3, 3.5, 3, 1.5]),
        EQPreset(name: "Late Night", gains: [-3, -2, -1, 0, 1, 2, 2, 1, -1, -3]),
    ]

    static func matching(_ gains: [Float]) -> EQPreset? {
        all.first { preset in zip(preset.gains, gains).allSatisfy { abs($0 - $1) < 0.01 } }
    }
}
