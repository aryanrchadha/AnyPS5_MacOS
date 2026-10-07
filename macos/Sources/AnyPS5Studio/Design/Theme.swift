import SwiftUI

/// Design tokens. One dark surface family, one cold accent, status hues reserved for state.
enum Theme {
    static let canvas = Color(red: 0.020, green: 0.020, blue: 0.024)
    static let shell = Color.white.opacity(0.035)
    static let core = Color(red: 0.047, green: 0.049, blue: 0.058).opacity(0.94)
    static let coreRaised = Color(red: 0.075, green: 0.078, blue: 0.090)
    static let hairline = Color.white.opacity(0.075)
    static let hairlineStrong = Color.white.opacity(0.14)

    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.36)

    static let accent = Color(red: 0.47, green: 0.87, blue: 0.80)
    static let orbTeal = Color(red: 0.10, green: 0.42, blue: 0.40)
    static let orbIndigo = Color(red: 0.20, green: 0.22, blue: 0.48)

    static let success = Color(red: 0.42, green: 0.86, blue: 0.56)
    static let warning = Color(red: 0.98, green: 0.76, blue: 0.33)
    static let failure = Color(red: 0.97, green: 0.47, blue: 0.47)

    static let outerRadius: CGFloat = 28
    static let bezel: CGFloat = 6
    static var innerRadius: CGFloat { outerRadius - bezel }
}

/// Spring and curve vocabulary. Nothing animates linearly.
enum Motion {
    static let settle = Animation.spring(response: 0.55, dampingFraction: 0.84)
    static let snap = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let reveal = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.9)
    static let drift = Animation.timingCurve(0.45, 0.05, 0.55, 0.95, duration: 22).repeatForever(autoreverses: true)
}

extension Font {
    static let display = Font.system(size: 40, weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 22, weight: .semibold, design: .default)
    static let cardTitle = Font.system(size: 15, weight: .semibold, design: .default)
    static let bodyText = Font.system(size: 13, weight: .regular, design: .default)
    static let captionText = Font.system(size: 11.5, weight: .regular, design: .default)
    static let eyebrow = Font.system(size: 9.5, weight: .medium, design: .default)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}
