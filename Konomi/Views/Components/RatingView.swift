import SwiftUI
import UIKit

// Shared 1–10 rating control
struct RatingView: View {
    let selectedScore: Int?
    let onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 5
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(1...10, id: \.self) { value in
                Button {
                    let feedback = UISelectionFeedbackGenerator()
                    feedback.prepare()
                    feedback.selectionChanged()
                    onSelect(value)
                } label: {
                    Text("\(value)")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected(value) ? KonomiTheme.persimmon : KonomiTheme.inkSecondary.opacity(0.12))
                        )
                        .foregroundStyle(isSelected(value) ? KonomiTheme.onPersimmon : KonomiTheme.ink)
                        .scaleEffect(isSelected(value) && !reduceMotion ? 1.06 : 1.0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) out of 10")
                .accessibilityAddTraits(isSelected(value) ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.2), value: selectedScore)
    }

    private func isSelected(_ value: Int) -> Bool {
        selectedScore == value
    }
}

// 1–5 star factor (rewatch / recommend)
struct FactorView: View {
    let label: String
    @Binding var value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.inkSecondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.2)) {
                            value = (value == i) ? 0 : i
                        }
                    } label: {
                        Image(systemName: i <= value ? "star.fill" : "star")
                            .font(.system(size: 18))
                            .foregroundStyle(i <= value ? KonomiTheme.persimmon : KonomiTheme.inkSecondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
