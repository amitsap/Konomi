import SwiftUI

enum KonomiTheme {
    static let canvas = Color("KonomiCanvas")
    static let surface = Color("KonomiSurface")
    static let surfaceRaised = Color("KonomiSurfaceRaised")
    static let ink = Color("KonomiInk")
    static let inkSecondary = Color("KonomiInkSecondary")
    static let hairline = Color("KonomiHairline")
    static let persimmon = Color("KonomiPersimmon")
    static let onPersimmon = Color("KonomiOnPersimmon")
    static let tasteViolet = Color("KonomiTasteViolet")
    static let success = Color("KonomiSuccess")

    static let heroRadius: CGFloat = 20
    static let sectionRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12
    static let coverRadius: CGFloat = 8

}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KonomiTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius))
            .overlay {
                RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius)
                    .stroke(KonomiTheme.hairline, lineWidth: 1)
            }
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

struct KonomiThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(KonomiTheme.persimmon)
    }
}

extension View {
    func konomiTheme() -> some View {
        modifier(KonomiThemeModifier())
    }
}

extension MediaStatus {
    var color: Color {
        switch self {
        case .wantTo: .blue
        case .inProgress: KonomiTheme.persimmon
        case .completed: KonomiTheme.success
        case .abandoned: KonomiTheme.inkSecondary
        }
    }
}

extension Int {
    var scoreColor: Color {
        switch self {
        case 9...10: KonomiTheme.persimmon
        case 7...8: .orange
        case 5...6: KonomiTheme.inkSecondary
        default: .red
        }
    }
}
