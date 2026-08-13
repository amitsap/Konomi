import SwiftData
import SwiftUI

struct TasteView: View {
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
    @Query(sort: \TasteProfile.lastUpdated, order: .reverse) private var profiles: [TasteProfile]
    @Query private var allItems: [MediaItem]
    @Query private var settings: [AppSettings]

    @State private var quickRateItem: MediaItem?
    @State private var hasTMDBKey = false
    @State private var hasAnthropicKey = false

    private enum Stage {
        case empty
        case building(Int)
        case readyToGenerate
        case mature(TasteProfile)
    }

    private var eligibleRatedItems: [MediaItem] {
        completedItems.filter { $0.personalScore != nil }
    }

    private var rateNextItems: [MediaItem] {
        Array(completedItems.filter { $0.personalScore == nil }.prefix(3))
    }

    private var stage: Stage {
        if allItems.isEmpty { return .empty }
        if let profile = profiles.first { return .mature(profile) }
        let ratedCount = eligibleRatedItems.count
        return ratedCount >= TasteAnalysisService.minimumRatedItems
            ? .readyToGenerate
            : .building(ratedCount)
    }

    var body: some View {
        @Bindable var navigationState = navigationState

        NavigationStack(path: $navigationState.tastePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    switch stage {
                    case .empty:
                        emptyComposition
                    case .building(let ratedCount):
                        progressHero(ratedCount: ratedCount, ready: false)
                        continueSection
                        rateNextSection
                    case .readyToGenerate:
                        progressHero(ratedCount: eligibleRatedItems.count, ready: true)
                        continueSection
                        rateNextSection
                    case .mature(let profile):
                        matureHero(profile)
                        continueSection
                        if let recommendation = recommendations.first {
                            nextRecommendation(recommendation)
                        }
                        yearSummary
                        if rateNextItems.isEmpty {
                            recentlyCompletedSection
                        } else {
                            rateNextSection
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(KonomiTheme.canvas)
            .navigationTitle("Konomi")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        navigationState.navigateToTaste(.settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")

                    Button {
                        navigationState.showAddSheet = true
                    } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add Media")
                }
            }
            .navigationDestination(for: TasteRoute.self) { route in
                switch route {
                case .media(let item):
                    MediaDetailView(item: item)
                case .profile:
                    TasteProfileView().navigationBarTitleDisplayMode(.inline)
                case .insights:
                    StatisticsView().navigationBarTitleDisplayMode(.inline)
                case .settings:
                    SettingsView().navigationBarTitleDisplayMode(.large)
                case .connections:
                    ConnectionsView().navigationBarTitleDisplayMode(.large)
                }
            }
            .sheet(item: $quickRateItem) { QuickRateSheet(item: $0) }
            .onAppear(perform: refreshRequiredKeyAvailability)
            .onChange(of: navigationState.selectedTab) { _, selectedTab in
                if selectedTab == .taste { refreshRequiredKeyAvailability() }
            }
        }
    }

    private var emptyComposition: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("好み · personal taste")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KonomiTheme.persimmon)
                    .textCase(.uppercase)
                Text("Teach Konomi what you love")
                    .font(.largeTitle.bold())
                    .fontDesign(.serif)
                    .foregroundStyle(KonomiTheme.ink)
                Text("Your library and ratings stay on this device. Add a few favorites so Konomi can begin learning your taste.")
                    .foregroundStyle(KonomiTheme.inkSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                if hasTMDBKey {
                    Button("Quick Setup · Recommended") { navigationState.showQuickSetup = true }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Add one title") { navigationState.showAddSheet = true }
                        .buttonStyle(.borderedProminent)
                }

                if hasTMDBKey {
                    Button("Add one title") { navigationState.showAddSheet = true }
                } else {
                    Button("Connect TMDB for Quick Setup") {
                        navigationState.navigateToTaste(.connections)
                    }
                }
                Button("Import Goodreads") { navigationState.showGoodreadsImport = true }
            }
            .controlSize(.large)

            if !hasAnthropicKey || !hasTMDBKey {
                Button {
                    navigationState.navigateToTaste(.connections)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "key.horizontal")
                            .foregroundStyle(KonomiTheme.persimmon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connections").font(.headline)
                            Text(connectionSummary)
                                .font(.subheadline)
                                .foregroundStyle(KonomiTheme.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KonomiTheme.inkSecondary)
                    }
                    .padding(16)
                    .background(KonomiTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.controlRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: KonomiTheme.controlRadius)
                            .stroke(KonomiTheme.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func progressHero(ratedCount: Int, ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("好み · personal taste")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KonomiTheme.persimmon)
                .textCase(.uppercase)
            ViewThatFits {
                HStack(alignment: .center, spacing: 20) {
                    progressHeroText(ratedCount: ratedCount, ready: ready)
                    TasteContourView(strength: ready ? .full : .compact)
                        .frame(width: 112, height: 112)
                }
                VStack(alignment: .leading, spacing: 16) {
                    TasteContourView(strength: ready ? .full : .compact)
                        .frame(width: 96, height: 96)
                    progressHeroText(ratedCount: ratedCount, ready: ready)
                }
            }
        }
        .padding(20)
        .background(KonomiTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.heroRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KonomiTheme.heroRadius)
                .stroke(KonomiTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(ratedCount) of \(TasteAnalysisService.minimumRatedItems) completed ratings")
    }

    private func progressHeroText(ratedCount: Int, ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ready ? "Ready to reveal your taste" : "Your taste is taking shape")
                .font(.title2.bold()).fontDesign(.serif)
            Text("\(ratedCount) of \(TasteAnalysisService.minimumRatedItems) completed ratings")
                .foregroundStyle(KonomiTheme.inkSecondary)
            ProgressView(value: Double(min(ratedCount, TasteAnalysisService.minimumRatedItems)), total: Double(TasteAnalysisService.minimumRatedItems))
            if ready {
                Button(hasAnthropicKey ? "Generate profile" : "Connect Anthropic") {
                    navigationState.navigateToTaste(hasAnthropicKey ? .profile : .connections)
                }
                .buttonStyle(.borderedProminent)
            } else if let item = rateNextItems.first {
                Button("Rate \(item.title)") { quickRateItem = item }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Open Library") { navigationState.selectedTab = .library }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func matureHero(_ profile: TasteProfile) -> some View {
        Button {
            navigationState.tastePath.append(.profile)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                Text("好み · personal taste")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KonomiTheme.persimmon)
                    .textCase(.uppercase)
                ViewThatFits {
                    HStack(alignment: .center, spacing: 20) {
                        profileText(profile)
                        TasteContourView().frame(width: 112, height: 112)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        TasteContourView().frame(width: 96, height: 96)
                        profileText(profile)
                    }
                }
            }
            .padding(20)
            .background(KonomiTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.heroRadius))
            .overlay {
                RoundedRectangle(cornerRadius: KonomiTheme.heroRadius)
                    .stroke(KonomiTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your taste profile. \(profile.tasteDescription)")
        .accessibilityValue("Based on \(eligibleRatedItems.count) ratings, updated \(profile.formattedDate)")
        .accessibilityHint("Opens your full Taste Profile")
    }

    private func profileText(_ profile: TasteProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(profile.tasteDescription)
                .font(.title3).fontDesign(.serif)
                .lineLimit(2)
                .foregroundStyle(KonomiTheme.ink)
            if !profile.favoriteGenres.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(profile.favoriteGenres.prefix(3)), id: \.self) { genre in
                        Text(genre)
                            .font(.caption.weight(.medium))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(KonomiTheme.persimmon.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
            }
            Text("Based on \(eligibleRatedItems.count) ratings · Updated \(profile.lastUpdated.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var continueSection: some View {
        if !inProgressItems.isEmpty {
            mediaRail(title: "Continue", items: Array(inProgressItems.prefix(5)))
        }
    }

    @ViewBuilder
    private var rateNextSection: some View {
        if !rateNextItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Rate next")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(rateNextItems) { item in
                            Button { quickRateItem = item } label: {
                                MediaCard(item: item, style: .compact, showPublic: settings.first?.showPublicScores ?? true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens Quick Rate")
                        }
                    }
                }
            }
        }
    }

    private func mediaRail(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: TasteRoute.media(item)) {
                            MediaCard(item: item, style: .compact, showPublic: settings.first?.showPublicScores ?? true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func nextRecommendation(_ recommendation: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Next for you", actionLabel: "Discover") {
                navigationState.selectedTab = .discover
            }
            RecommendationCompactCard(recommendation: recommendation)
        }
    }

    private var yearSummary: some View {
        Button {
            navigationState.tastePath.append(.insights)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your year").font(.headline)
                    Text(yearSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(KonomiTheme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(KonomiTheme.persimmon)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KonomiTheme.inkSecondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Insights")
    }

    @ViewBuilder
    private var recentlyCompletedSection: some View {
        let recent = Array(completedItems.prefix(5))
        if !recent.isEmpty { mediaRail(title: "Recently completed", items: recent) }
    }

    private var yearSummaryText: String {
        let calendar = Calendar.current
        let items = completedItems.filter {
            guard let date = $0.dateCompleted else { return false }
            return calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        }
        let scores = items.compactMap(\.personalScore)
        let average = scores.isEmpty ? "No scores yet" : String(format: "%.1f average", Double(scores.reduce(0, +)) / Double(scores.count))
        return "\(items.count) completed · \(average)"
    }

    private var connectionSummary: String {
        switch (hasAnthropicKey, hasTMDBKey) {
        case (false, false): "Anthropic and TMDB needed"
        case (false, true): "Anthropic needed"
        case (true, false): "TMDB needed"
        case (true, true): "Required services connected"
        }
    }

    private func refreshRequiredKeyAvailability() {
        hasTMDBKey = KeychainService.hasUsableTMDBKey()
        hasAnthropicKey = KeychainService.hasUsableAnthropicKey()
    }
}

struct RecommendationCompactCard: View {
    @Bindable var recommendation: Recommendation
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            navigationState.selectedTab = .discover
        } label: {
            HStack(spacing: 14) {
                CoverImageView(
                    urlString: recommendation.coverURLString,
                    cachedData: recommendation.coverImageData,
                    mediaType: recommendation.mediaType,
                    width: 72,
                    height: 108
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(KonomiTheme.ink)
                    Text(recommendation.creator)
                        .font(.subheadline)
                        .foregroundStyle(KonomiTheme.inkSecondary)
                        .lineLimit(1)
                    Text("For you \(recommendation.predictedScoreDisplay)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KonomiTheme.persimmon)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(KonomiTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius))
            .overlay {
                RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius)
                    .stroke(KonomiTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .task { await BookCoverService.enrichIfNeeded(for: recommendation, in: context) }
    }
}
