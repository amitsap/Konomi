import SwiftUI

// MARK: - Color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Theme

enum KonomiTheme {
    static let background   = Color(hex: "#F2F2F7")
    static let card         = Color.white
    static let primary      = Color(hex: "#FF6B35")   // warm orange — personal score
    static let text         = Color(hex: "#1C1C1E")
    static let secondary    = Color(hex: "#6C6C70")   // de-emphasised / public scores
    static let serendipity  = Color(hex: "#5E5CE6")   // indigo — bubble-breaking picks
    static let success      = Color(hex: "#30D158")
    static let cardRadius: CGFloat = 12
    static let coverRadius: CGFloat = 8
}

// MARK: - Card style

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KonomiTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.cardRadius))
            .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - App-wide theme modifier

struct KonomiThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(.light)
            .tint(KonomiTheme.primary)
    }
}

extension View {
    func konomiTheme() -> some View {
        modifier(KonomiThemeModifier())
    }
}

// MARK: - Status colour

extension MediaStatus {
    var color: Color {
        switch self {
        case .wantTo:     return Color(hex: "#0A84FF")
        case .inProgress: return KonomiTheme.primary
        case .completed:  return KonomiTheme.success
        case .abandoned:  return KonomiTheme.secondary
        }
    }
}

// MARK: - Score colours

extension Int {
    var scoreColor: Color {
        switch self {
        case 9...10: return KonomiTheme.primary
        case 7...8:  return Color(hex: "#FF9F0A")
        case 5...6:  return KonomiTheme.secondary
        default:     return Color(hex: "#FF453A")
        }
    }
}
