import SwiftUI

struct UndoNoticeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let message: String
    let messageAccessibilityLabel: String
    let actionAccessibilityLabel: String
    let onUndo: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                verticalLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalLayout
                    verticalLayout
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 12) {
            icon
            messageText
            Spacer(minLength: 8)
            undoButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardStyle()
        .shadow(color: colorScheme == .light ? .black.opacity(0.08) : .clear, radius: 8, y: 3)
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                icon
                messageText
            }
            undoButton
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardStyle()
        .shadow(color: colorScheme == .light ? .black.opacity(0.08) : .clear, radius: 8, y: 3)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(KonomiTheme.inkSecondary)
            .accessibilityHidden(true)
    }

    private var messageText: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(KonomiTheme.ink)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .accessibilityLabel(messageAccessibilityLabel)
    }

    private var undoButton: some View {
        Button("Undo", action: onUndo)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(KonomiTheme.persimmon)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(actionAccessibilityLabel)
    }
}
