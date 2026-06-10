import SwiftUI

// 1–10 tap rating row
struct RatingView: View {
    @Binding var score: Int?
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...10, id: \.self) { value in
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        score = (score == value) ? nil : value  // tap again to clear
                    }
                } label: {
                    Text("\(value)")
                        .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                        .frame(width: size, height: size)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected(value) ? KonomiTheme.primary : KonomiTheme.secondary.opacity(0.12))
                        )
                        .foregroundStyle(isSelected(value) ? .white : KonomiTheme.text)
                        .scaleEffect(isSelected(value) ? 1.1 : 1.0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isSelected(_ value: Int) -> Bool {
        guard let s = score else { return false }
        return value <= s
    }
}

// 1–5 star factor (rewatch / recommend)
struct FactorView: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.secondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        withAnimation(.spring(duration: 0.2)) {
                            value = (value == i) ? 0 : i
                        }
                    } label: {
                        Image(systemName: i <= value ? "star.fill" : "star")
                            .font(.system(size: 18))
                            .foregroundStyle(i <= value ? KonomiTheme.primary : KonomiTheme.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
