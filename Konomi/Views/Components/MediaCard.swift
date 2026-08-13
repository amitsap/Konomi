import SwiftUI
import SwiftData

enum MediaCardStyle { case compact, list }

struct MediaCard: View {
    let item: MediaItem
    var style: MediaCardStyle = .list
    let showPublic: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                .foregroundStyle(KonomiTheme.ink)
                .frame(width: 100, alignment: .leading)
        }
        .frame(width: 100)
    }

    // MARK: - List

    @ViewBuilder
    private var listCard: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityListCard
        } else {
            compactListCard
        }
    }

    private var compactListCard: some View {
        HStack(spacing: 12) {
            CoverImageView(
                urlString: item.coverURLString,
                cachedData: item.coverImageData,
                mediaType: item.mediaType,
                width: 56,
                height: 84
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                .foregroundStyle(KonomiTheme.ink)

                if !item.creator.isEmpty || item.year != nil {
                    Text(metadataLine)
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.inkSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    StatusBadge(status: item.status)
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(KonomiTheme.persimmon)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let score = item.personalScore {
                    VStack(alignment: .trailing, spacing: 1) {
                        ScoreBadge(score: score, size: 16)
                        Text("Your")
                            .font(.caption2)
                            .foregroundStyle(KonomiTheme.inkSecondary)
                    }
                }
                if showPublic, let pub = item.publicScore {
                    Text("Public \(Formatters.publicScore(pub))")
                        .font(.caption2)
                        .foregroundStyle(KonomiTheme.inkSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var accessibilityListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CoverImageView(
                    urlString: item.coverURLString,
                    cachedData: item.coverImageData,
                    mediaType: item.mediaType,
                    width: 56,
                    height: 84
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KonomiTheme.ink)

                    if !item.creator.isEmpty || item.year != nil {
                        Text(metadataLine)
                            .font(.caption)
                            .foregroundStyle(KonomiTheme.inkSecondary)
                    }
                }
            }

            HStack(spacing: 8) {
                StatusBadge(status: item.status)
                    .fixedSize(horizontal: true, vertical: false)
                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(KonomiTheme.persimmon)
                        .accessibilityLabel("Favorite")
                }
            }

            if item.personalScore != nil || (showPublic && item.publicScore != nil) {
                VStack(alignment: .leading, spacing: 6) {
                    if let score = item.personalScore {
                        Label("Your score: \(score) out of 10", systemImage: "star.fill")
                    }
                    if showPublic, let pub = item.publicScore {
                        Label("Public score: \(Formatters.publicScore(pub))", systemImage: "person.2.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var metadataLine: String {
        switch (item.creator.isEmpty, item.year) {
        case (false, let year?): "\(item.creator) · \(year)"
        case (false, nil): item.creator
        case (true, let year?): String(year)
        case (true, nil): ""
        }
    }
}
