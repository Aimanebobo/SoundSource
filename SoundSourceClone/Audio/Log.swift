import os

/// Inspect with: log stream --predicate 'subsystem == "com.example.SoundSourceClone"'
enum Log {
    static let capture = Logger(subsystem: "com.example.SoundSourceClone", category: "capture")
    static let ui = Logger(subsystem: "com.example.SoundSourceClone", category: "ui")
}
