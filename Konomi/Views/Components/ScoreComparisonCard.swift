import SwiftUI

struct ScoreComparisonCard: View {
    let personalScore: Int?
    let publicScore: Double?
    var showPublic = true

    var body: some View {
        ViewThatFits {
            HStack(alignment: .center, spacing: 20) { scoreContent }
            VStack(alignment: .leading, spacing: 16) { scoreContent }
        }
        .padding(16)
        .cardStyle()
    }

    @ViewBuilder
    private var scoreContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Formatters.score(personalScore))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(personalScore != nil ? KonomiTheme.persimmon : KonomiTheme.inkSecondary)
            Text("Your Score")
                .font(.caption.weight(.medium))
                .foregroundStyle(KonomiTheme.inkSecondary)
        }
        .accessibilityElement(children: .combine)

        if showPublic {
            Divider().frame(maxWidth: 50, maxHeight: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.publicScore(publicScore))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(KonomiTheme.inkSecondary)
                Text("Public")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(KonomiTheme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
        }

        if let personalScore, let publicScore, showPublic {
            Spacer(minLength: 0)
            Text(Formatters.scoreGapDescription(personal: personalScore, public: publicScore))
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
                .multilineTextAlignment(.leading)
        }
    }
}
