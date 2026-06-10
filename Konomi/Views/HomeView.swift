import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppNavigationState.self) private var navigationState

    @Query(filter: #Predicate<MediaItem> { $0.statusRaw == "inProgress" },
           sort: \MediaItem.dateStarted, order: .reverse)
    private var inProgressItems: [MediaItem]

    @Query(filter: #Predicate<MediaItem> { $0.statusRaw == "completed" },
           sort: \MediaItem.dateCompleted, order: .reverse)
    private var completedItems: [MediaItem]

    @Query(filter: #Predicate<Recommendation> { !$0.wasDismissed && !$0.wasAdded },
           sort: \Recommendation.generatedDate, order: .reverse)
    private var recommendations: [Recommendation]

    @Query private var allItems: [MediaItem]

    @State private var selectedItem: MediaItem?

    var recentlyCompleted: [MediaItem] { Array(completedItems.prefix(5)) }
    var featuredRecs: [Recommendation] { Array(recommendations.prefix(3)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // In Progress
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "In Progress")
                        if inProgressItems.isEmpty {
                            ContentUnavailableView(
                                "Nothing in Progress",
                                systemImage: "play.circle",
                                description: Text("Start something new")
                            )
                            .frame(height: 120)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(inProgressItems) { item in
                                        NavigationLink(value: item) {
                                            MediaCard(item: item, style: .compact)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    // Recently Completed
                    if !recentlyCompleted.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Recently Completed")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(recentlyCompleted) { item in
                                        NavigationLink(value: item) {
                                            MediaCard(item: item, style: .compact)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    // For You
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "For You",
                            actionLabel: featuredRecs.isEmpty ? nil : "See All"
                        ) {
                            navigationState.selectedTab = .recommendations
                        }
                        if featuredRecs.isEmpty {
                            ContentUnavailableView(
                                "No Recommendations Yet",
                                systemImage: "sparkles",
                                description: Text("Rate 10+ items to unlock personalised picks")
                            )
                            .frame(height: 120)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(featuredRecs) { rec in
                                        RecommendationCompactCard(recommendation: rec)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    // Stats strip
                    statsStrip
                        .padding(.horizontal, 20)

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }
            .background(KonomiTheme.background)
            .navigationTitle("好み")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        navigationState.showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
            }
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell(
                value: allItems.filter { $0.mediaType == .book && $0.isCompleted }.count,
                label: "Books"
            )
            Divider().frame(height: 36)
            statCell(
                value: allItems.filter { $0.mediaType == .movie && $0.isCompleted }.count,
                label: "Movies"
            )
            Divider().frame(height: 36)
            statCell(
                value: allItems.filter { $0.mediaType == .tvShow && $0.isCompleted }.count,
                label: "Shows"
            )
        }
        .padding(16)
        .cardStyle()
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(KonomiTheme.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(KonomiTheme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Small recommendation card for home screen
struct RecommendationCompactCard: View {
    @Bindable var recommendation: Recommendation
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            navigationState.selectedTab = .recommendations
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    CoverImageView(
                        urlString: recommendation.coverURLString,
                        cachedData: recommendation.coverImageData,
                        mediaType: recommendation.mediaType,
                        width: 100,
                        height: 150
                    )
                    if recommendation.isSerendipitous {
                        Text("🎲")
                            .font(.caption)
                            .padding(5)
                            .background(KonomiTheme.serendipity.opacity(0.85))
                            .clipShape(Circle())
                            .padding(5)
                    }
                }
                Text(recommendation.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(KonomiTheme.text)
                    .frame(width: 100, alignment: .leading)
                Text(recommendation.predictedScoreDisplay)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KonomiTheme.primary)
            }
            .frame(width: 100)
        }
        .buttonStyle(.plain)
        .task {
            await BookCoverService.enrichIfNeeded(for: recommendation, in: context)
        }
    }
}
