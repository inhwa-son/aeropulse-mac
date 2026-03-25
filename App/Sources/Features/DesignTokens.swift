import SwiftUI
import AppKit

// MARK: - Design Tokens
//
// Semantic color system with automatic light/dark adaptation.
// Uses perceptually uniform values for consistent appearance across hues.

enum APColor {

    // MARK: - Thermal Scale
    // Temperature-driven colors with optimised contrast per appearance.
    // Dark mode uses higher lightness values for improved contrast.

    /// < 45 °C — cool / idle
    static let thermalCool = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.40, green: 0.72, blue: 1.00, alpha: 1)   // bright sky blue
            : NSColor(srgbRed: 0.12, green: 0.46, blue: 0.86, alpha: 1)   // deep blue
    })

    /// 45–60 °C — normal
    static let thermalNormal = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.30, green: 0.84, blue: 0.56, alpha: 1)   // vivid mint
            : NSColor(srgbRed: 0.08, green: 0.52, blue: 0.30, alpha: 1)   // deep green (WCAG AA)
    })

    /// 60–75 °C — warm
    static let thermalWarm = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.00, green: 0.76, blue: 0.28, alpha: 1)   // bright amber
            : NSColor(srgbRed: 0.62, green: 0.38, blue: 0.00, alpha: 1)   // deep amber (WCAG AA ≥4.5:1)
    })

    /// > 75 °C — hot / critical
    static let thermalHot = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.00, green: 0.42, blue: 0.38, alpha: 1)   // bright coral red
            : NSColor(srgbRed: 0.82, green: 0.18, blue: 0.18, alpha: 1)   // deep red
    })

    // MARK: - Status Semantics (fill · content · border)

    static let statusSuccess = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.24, green: 0.82, blue: 0.52, alpha: 1)
            : NSColor(srgbRed: 0.08, green: 0.53, blue: 0.32, alpha: 1)
    })

    static let statusWarning = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.00, green: 0.72, blue: 0.24, alpha: 1)
            : NSColor(srgbRed: 0.60, green: 0.36, blue: 0.00, alpha: 1)   // WCAG AA ≥4.5:1
    })

    static let statusError = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.00, green: 0.40, blue: 0.36, alpha: 1)
            : NSColor(srgbRed: 0.82, green: 0.18, blue: 0.18, alpha: 1)
    })

    static let statusInfo = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.40, green: 0.72, blue: 1.00, alpha: 1)
            : NSColor(srgbRed: 0.14, green: 0.46, blue: 0.86, alpha: 1)
    })

    /// Neutral accent for XPC / alternative states
    static let statusNeutral = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.46, green: 0.80, blue: 0.78, alpha: 1)   // teal-mint
            : NSColor(srgbRed: 0.12, green: 0.46, blue: 0.44, alpha: 1)   // WCAG AA ≥4.5:1
    })

    // MARK: - Surface / Background Layers

    /// Tinted card fill — adapts opacity per appearance for readability
    static func tintedFill(_ tint: Color, prominent: Bool = false) -> Color {
        tint.opacity(prominent ? 0.14 : 0.08)
    }

    /// Tinted card stroke
    static func tintedBorder(_ tint: Color, prominent: Bool = false) -> Color {
        tint.opacity(prominent ? 0.28 : 0.14)
    }

    // MARK: - Chart Palette (5 categorical colors)

    static let chart1 = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.40, green: 0.72, blue: 1.00, alpha: 1)
            : NSColor(srgbRed: 0.14, green: 0.46, blue: 0.86, alpha: 1)
    })

    static let chart2 = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.30, green: 0.84, blue: 0.56, alpha: 1)
            : NSColor(srgbRed: 0.06, green: 0.50, blue: 0.28, alpha: 1)   // WCAG AA ≥4.5:1
    })

    static let chart3 = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.00, green: 0.72, blue: 0.24, alpha: 1)
            : NSColor(srgbRed: 0.62, green: 0.38, blue: 0.00, alpha: 1)   // WCAG AA ≥4.5:1
    })

    static let chart4 = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.76, green: 0.50, blue: 1.00, alpha: 1)
            : NSColor(srgbRed: 0.48, green: 0.24, blue: 0.82, alpha: 1)
    })

    static let chart5 = Color(nsColor: .init(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.00, green: 0.42, blue: 0.62, alpha: 1)
            : NSColor(srgbRed: 0.78, green: 0.18, blue: 0.40, alpha: 1)
    })

    // MARK: - Thermal Accent Resolution

    /// Maps a temperature value to the appropriate thermal color.
    static func thermalAccent(for celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        switch celsius {
        case ..<45:
            return thermalCool
        case ..<60:
            return thermalNormal
        case ..<75:
            return thermalWarm
        default:
            return thermalHot
        }
    }

    // MARK: - Backend State Mapping

    static func backendAccent(for state: FanWriteBackendState) -> Color {
        switch state {
        case .privilegedDaemon:
            return statusSuccess
        case .awaitingApproval:
            return statusWarning
        case .noFansDetected:
            return statusNeutral
        case .fallbackCLI:
            return statusWarning
        case .unavailable:
            return statusError
        case .booting:
            return statusInfo
        }
    }

    // MARK: - Helper Checkpoint State Mapping

    static func helperCheckpointAccent(for state: HelperSetupStepState) -> Color {
        switch state {
        case .complete:
            return statusSuccess
        case .actionRequired:
            return statusWarning
        case .pendingApproval:
            return statusInfo
        }
    }

    // MARK: - Integration State Mapping

    static func integrationAccent(for state: IntegrationState) -> Color {
        switch state {
        case .ready:
            return statusInfo
        case .awaitingApproval:
            return statusWarning
        case .missingFanCLI, .missingISMC:
            return statusWarning
        case .failed:
            return statusError
        }
    }
}

// MARK: - NSAppearance Helpers

// MARK: - Domain Localization Extensions (Features layer — has access to String.tr)

extension FanMode {
    @MainActor var localizedTitle: String {
        switch self {
        case .auto: String.tr("fan.mode.auto")
        case .manual: String.tr("fan.mode.manual")
        case .unknown: String.tr("fan.mode.unknown")
        }
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - Tinted Card Modifier

struct TintedCardStyle: ViewModifier {
    let tint: Color
    var cornerRadius: CGFloat = 20
    var prominent: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(APColor.tintedFill(tint, prominent: prominent))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(APColor.tintedBorder(tint, prominent: prominent), lineWidth: 1)
            )
    }
}

extension View {
    func tintedCard(_ tint: Color, cornerRadius: CGFloat = 20, prominent: Bool = false) -> some View {
        modifier(TintedCardStyle(tint: tint, cornerRadius: cornerRadius, prominent: prominent))
    }

    /// Panel section style — translucent material background with subtle border
    func panelSection(cornerRadius: CGFloat = 14) -> some View {
        padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    /// Card style — translucent material background with full-width layout and subtle border
    func cardStyle() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}
