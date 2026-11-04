import SwiftUI

enum Theme {
    static let panelWidth: CGFloat = 690
    static let cornerRadius: CGFloat = 12
    static let rowHeight: CGFloat = 34
    static let nameColumn: CGFloat = 112
    static let percentColumn: CGFloat = 40
    static let deviceColumn: CGFloat = 190

    static let accent = Color(red: 0.32, green: 0.60, blue: 1.0)
    static let favorite = Color(red: 1.0, green: 0.79, blue: 0.24)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.33)

    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.36)

    static let controlFill = Color.white.opacity(0.07)
    static let controlStroke = Color.white.opacity(0.11)
    static let separator = Color.white.opacity(0.08)
    static let hover = Color.white.opacity(0.045)
    static let cardFill = Color.black.opacity(0.22)
    static let track = Color.white.opacity(0.13)
    static let snapshotBackground = Color(red: 0.135, green: 0.135, blue: 0.15)

    static let meter = LinearGradient(
        stops: [
            .init(color: Color(red: 0.20, green: 0.82, blue: 0.43), location: 0),
            .init(color: Color(red: 0.50, green: 0.88, blue: 0.32), location: 0.62),
            .init(color: Color(red: 1.00, green: 0.80, blue: 0.22), location: 0.84),
            .init(color: Color(red: 1.00, green: 0.33, blue: 0.28), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)

    static let proBadge = LinearGradient(colors: [Color(red: 0.55, green: 0.38, blue: 1.0), Color(red: 0.25, green: 0.55, blue: 1.0)],
                                         startPoint: .leading, endPoint: .trailing)
    static let trialBadge = LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.20), Color(red: 0.95, green: 0.38, blue: 0.25)],
                                           startPoint: .leading, endPoint: .trailing)

    static func percent(_ value: Float) -> String { "\(Int((value * 100).rounded()))%" }
}

enum RowExpansion: Equatable {
    case effects
    case details
}
