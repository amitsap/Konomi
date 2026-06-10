import SwiftUI

struct StatusBadge: View {
    let status: MediaStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.15))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }
}

struct ScoreBadge: View {
    let score: Int
    var size: CGFloat = 14

    var body: some View {
        Text("\(score)")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size * 1.8, height: size * 1.8)
            .background(score.scoreColor)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
