import SwiftUI

struct SectionHeader: View {
    let title: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(KonomiTheme.text)
            Spacer()
            if let label = actionLabel, let action {
                Button(label, action: action)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(KonomiTheme.primary)
            }
        }
        .padding(.horizontal, 20)
    }
}
