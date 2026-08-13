import SwiftUI

struct QuickRateSheet: View {
    @Bindable var item: MediaItem
    @Environment(\.dismiss) private var dismiss

    @State private var shouldMarkCompleted: Bool

    init(item: MediaItem) {
        self.item = item
        _shouldMarkCompleted = State(initialValue: item.status == .inProgress)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    itemContext

                    if item.status != .completed {
                        Toggle("Mark as Completed", isOn: $shouldMarkCompleted)
                            .font(.subheadline.weight(.semibold))
                            .tint(KonomiTheme.persimmon)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(shouldMarkCompleted && item.status != .completed
                             ? "Choose a score to save and mark completed."
                             : "Choose a score to save.")
                            .font(.subheadline)
                            .foregroundStyle(KonomiTheme.inkSecondary)

                        RatingView(selectedScore: item.personalScore) { score in
                            item.personalScore = score
                            if shouldMarkCompleted && item.status != .completed {
                                item.markCompleted()
                            }
                            dismiss()
                        }
                    }
                    .padding(16)
                    .cardStyle()
                }
                .padding(20)
            }
            .background(KonomiTheme.canvas)
            .navigationTitle("Quick Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if item.personalScore != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(role: .destructive) {
                                item.personalScore = nil
                                dismiss()
                            } label: {
                                Label("Remove Rating", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Rating Options")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var itemContext: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImageView(
                urlString: item.coverURLString,
                cachedData: item.coverImageData,
                mediaType: item.mediaType,
                width: 72,
                height: 108
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(KonomiTheme.ink)
                    .lineLimit(2)

                if let metadata = metadataText {
                    Text(metadata)
                        .font(.subheadline)
                        .foregroundStyle(KonomiTheme.inkSecondary)
                }

                StatusBadge(status: item.status)
            }

            Spacer(minLength: 0)
        }
    }

    private var metadataText: String? {
        let values = [
            item.creator.isEmpty ? nil : item.creator,
            item.year.map(String.init),
        ].compactMap { $0 }

        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}
