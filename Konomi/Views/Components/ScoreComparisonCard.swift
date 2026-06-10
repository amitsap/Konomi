import SwiftUI

struct ScoreComparisonCard: View {
    let personalScore: Int?
    let publicScore: Double?
    var showPublic: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            // Personal score — primary
            VStack(spacing: 2) {
                Text(Formatters.score(personalScore))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(personalScore != nil ? KonomiTheme.primary : KonomiTheme.secondary)
                Text("Your Score")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(KonomiTheme.secondary)
            }

            Divider()
                .frame(height: 50)

            // Public score — de-emphasised
            if showPublic {
                VStack(spacing: 2) {
                    Text(Formatters.publicScore(publicScore))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(KonomiTheme.secondary)
                    Text("Public")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(KonomiTheme.secondary.opacity(0.7))
                }
            }

            if let personal = personalScore, let pub = publicScore, showPublic {
                Spacer()
                Text(Formatters.scoreGapDescription(personal: personal, public: pub))
                    .font(.caption)
                    .foregroundStyle(KonomiTheme.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(16)
        .cardStyle()
    }
}
