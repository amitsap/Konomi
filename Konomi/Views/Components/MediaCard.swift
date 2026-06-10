import SwiftUI
import SwiftData

enum MediaCardStyle { case compact, list }

struct MediaCard: View {
    let item: MediaItem
    var style: MediaCardStyle = .list
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            switch style {
            case .compact: compactCard
            case .list: listCard
            }
        }
        .task {
            await BookCoverService.enrichIfNeeded(for: item, in: context)
        }
    }

    // MARK: - Compact (horizontal scroll)

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                CoverImageView(
                    urlString: item.coverURLString,
                    cachedData: item.coverImageData,
                    mediaType: item.mediaType,
                    width: 100,
                    height: 150
                )
                if let score = item.personalScore {
                    ScoreBadge(score: score)
                        .padding(6)
                }
            }
            Text(item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(KonomiTheme.text)
                .frame(width: 100, alignment: .leading)
        }
        .frame(width: 100)
    }

    // MARK: - List

    private var listCard: some View {
        HStack(spacing: 12) {
            CoverImageView(
                urlString: item.coverURLString,
                cachedData: item.coverImageData,
                mediaType: item.mediaType,
                width: 60,
                height: 90
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(KonomiTheme.text)

                if !item.creator.isEmpty {
                    Text(item.creator)
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.secondary)
                }

                if let year = item.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.secondary)
                }

                HStack(spacing: 6) {
                    StatusBadge(status: item.status)
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(KonomiTheme.primary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let score = item.personalScore {
                    ScoreBadge(score: score, size: 16)
                }
                if let pub = item.publicScore {
                    Text(Formatters.publicScore(pub))
                        .font(.caption2)
                        .foregroundStyle(KonomiTheme.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
