import SwiftUI

struct EmotionalResponsePicker: View {
    @Binding var selected: [EmotionalResponse]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EmotionalResponse.allCases, id: \.self) { response in
                    let isOn = selected.contains(response)
                    Button {
                        withAnimation(.spring(duration: 0.2)) {
                            if isOn {
                                selected.removeAll { $0 == response }
                            } else {
                                selected.append(response)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(response.emoji)
                                .font(.body)
                            Text(response.displayName)
                                .font(.subheadline.weight(isOn ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isOn ? KonomiTheme.serendipity : KonomiTheme.secondary.opacity(0.1))
                        .foregroundStyle(isOn ? .white : KonomiTheme.text)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct MoodTagGrid: View {
    @Binding var selected: [MoodTag]
    var interactive = true

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(MoodTag.allCases, id: \.self) { tag in
                let isOn = selected.contains(tag)
                Button {
                    guard interactive else { return }
                    withAnimation(.spring(duration: 0.2)) {
                        if isOn {
                            selected.removeAll { $0 == tag }
                        } else {
                            selected.append(tag)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tag.emoji)
                            .font(.subheadline)
                        Text(tag.displayName)
                            .font(.subheadline.weight(isOn ? .semibold : .regular))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isOn ? KonomiTheme.primary.opacity(0.15) : KonomiTheme.secondary.opacity(0.1))
                    .foregroundStyle(isOn ? KonomiTheme.primary : KonomiTheme.text)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!interactive)
            }
        }
    }
}

// Simple wrapping flow layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        var y: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
