import SwiftUI

struct SerendipityBadge: View {
    let score: Double
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Text("🎲")
                .font(compact ? .caption2 : .caption)
            Text(compact ? "Hidden Gem" : Formatters.serendipityLabel(score))
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 3)
        .background(KonomiTheme.serendipity.opacity(0.12))
        .foregroundStyle(KonomiTheme.serendipity)
        .clipShape(Capsule())
    }
}
