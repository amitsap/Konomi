import SwiftUI
import SwiftData

struct RecommendationsView: View {
    @Environment(TasteAnalysisService.self) private var tasteService
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Recommendation> { !$0.wasDismissed },
           sort: \Recommendation.generatedDate, order: .reverse)
    private var recommendations: [Recommendation]

    @Query(filter: #Predicate<MediaItem> { $0.statusRaw == "completed" })
    private var completedItems: [MediaItem]

    @Query private var tasteProfiles: [TasteProfile]

    @State private var mode: RecommendationMode = .standard
    @State private var errorMessage: String?
    @State private var showError = false

    private var displayedRecs: [Recommendation] {
        switch mode {
        case .standard: return recommendations.filter { !$0.isSerendipitous || recommendations.count < 5 }
        case .surpriseMe: return recommendations.filter(\.isSerendipitous)
        }
    }

    private var canGenerate: Bool { completedItems.count >= 5 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                Picker("Mode", selection: $mode) {
                    Text("For You").tag(RecommendationMode.standard)
                    Text("Surprise Me").tag(RecommendationMode.surpriseMe)
                }
                .pickerStyle(.segmented)
                .padding(16)

                if mode == .surpriseMe {
                    surpriseBanner
                }

                if tasteService.isGenerating {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Analysing your taste...")
                            .font(.subheadline)
                            .foregroundStyle(KonomiTheme.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if !canGenerate {
                    ContentUnavailableView(
                        "Not Enough Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Rate \(5 - completedItems.count) more completed items to unlock recommendations")
                    )
                    .frame(maxHeight: .infinity)
                } else if displayedRecs.isEmpty {
                    generatePrompt
                } else {
                    recommendationsList
                }
            }
            .background(KonomiTheme.background)
            .navigationTitle(mode == .standard ? "For You" : "Surprise Me")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await generateRecommendations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(tasteService.isGenerating || !canGenerate)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Something went wrong")
            }
        }
    }

    // MARK: - Subviews

    private var surpriseBanner: some View {
        HStack(spacing: 8) {
            Text("🎲")
            Text("Ignoring the crowd — finding your hidden gems")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KonomiTheme.serendipity)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(KonomiTheme.serendipity.opacity(0.08))
    }

    private var generatePrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: mode == .surpriseMe ? "dice" : "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(mode == .surpriseMe ? KonomiTheme.serendipity : KonomiTheme.primary)
            Text(mode == .surpriseMe ? "Ready to break the bubble?" : "Discover your next favourite")
                .font(.title3.weight(.semibold))
            Button {
                Task { await generateRecommendations() }
            } label: {
                Label("Generate Recommendations", systemImage: "sparkles")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(mode == .surpriseMe ? KonomiTheme.serendipity : KonomiTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var recommendationsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(displayedRecs) { rec in
                    RecommendationCard(recommendation: rec, surpriseMode: mode == .surpriseMe)
                        .padding(.horizontal, 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 16)
            .animation(.spring(duration: 0.3), value: displayedRecs.map(\.id))
        }
    }

    // MARK: - Actions

    @MainActor
    private func generateRecommendations() async {
        let profile = tasteProfiles.sorted { $0.lastUpdated > $1.lastUpdated }.first
        var activeProfile = profile

        // Generate profile if missing or stale
        if activeProfile == nil || (activeProfile?.isStale == true) {
            do {
                let newProfile = try await tasteService.generateTasteProfile(items: Array(completedItems))
                context.insert(newProfile)
                try? context.save()
                activeProfile = newProfile
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                return
            }
        }

        guard let p = activeProfile else { return }

        do {
            let allItems = try context.fetch(FetchDescriptor<MediaItem>())
            let newRecs = try await tasteService.generateRecommendations(
                profile: p,
                existingLibrary: allItems,
                surpriseMode: mode == .surpriseMe
            )
            for rec in newRecs { context.insert(rec) }
            try? context.save()

            // Cache covers in background
            for rec in newRecs {
                await CoverImageService.cacheIfNeeded(for: rec)
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Recommendation card

struct RecommendationCard: View {
    @Bindable var recommendation: Recommendation
    var surpriseMode: Bool = false
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CoverImageView(
                    urlString: recommendation.coverURLString,
                    cachedData: recommendation.coverImageData,
                    mediaType: recommendation.mediaType,
                    width: 70,
                    height: 105
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.title)
                        .font(.headline)
                        .foregroundStyle(KonomiTheme.text)
                        .lineLimit(2)

                    if !recommendation.creator.isEmpty {
                        Text(recommendation.creator)
                            .font(.subheadline)
                            .foregroundStyle(KonomiTheme.secondary)
                    }

                    HStack(spacing: 8) {
                        // Predicted score — prominent
                        HStack(spacing: 3) {
                            Text(recommendation.predictedScoreDisplay)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(surpriseMode ? KonomiTheme.serendipity : KonomiTheme.primary)
                            Text("predicted")
                                .font(.caption)
                                .foregroundStyle(KonomiTheme.secondary)
                        }

                        // Public score — small, grey
                        if let pub = recommendation.publicScore {
                            Text("Public: \(Formatters.publicScore(pub))")
                                .font(.caption)
                                .foregroundStyle(KonomiTheme.secondary.opacity(0.7))
                        }
                    }

                    if recommendation.isSerendipitous {
                        SerendipityBadge(score: recommendation.serendipityScore, compact: true)
                    }
                }
                Spacer()
            }

            // Why text
            Text(recommendation.recommendationReason)
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            // Serendipity explanation
            if let explanation = recommendation.serendipityExplanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(KonomiTheme.serendipity)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Actions
            HStack(spacing: 12) {
                Button {
                    addToLibrary()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(surpriseMode ? KonomiTheme.serendipity : KonomiTheme.primary)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                Button {
                    recommendation.wasDismissed = true
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(KonomiTheme.secondary.opacity(0.1))
                        .foregroundStyle(KonomiTheme.secondary)
                        .clipShape(Capsule())
                }
                Spacer()
            }
        }
        .padding(16)
        .background(surpriseMode
            ? KonomiTheme.serendipity.opacity(0.05)
            : KonomiTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KonomiTheme.cardRadius)
                .stroke(surpriseMode ? KonomiTheme.serendipity.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .task {
            await BookCoverService.enrichIfNeeded(for: recommendation, in: context)
        }
    }

    private func addToLibrary() {
        let item = MediaItem()
        item.title = recommendation.title
        item.creator = recommendation.creator
        item.year = recommendation.year
        item.coverURLString = recommendation.coverURLString
        item.coverImageData = recommendation.coverImageData
        item.publicScore = recommendation.publicScore
        item.synopsis = recommendation.synopsis
        item.genres = recommendation.genres
        item.mediaType = recommendation.mediaType
        item.status = .wantTo
        item.dateAdded = Date()
        item.recommendedByAI = true
        item.serendipityScore = recommendation.serendipityScore
        item.recommendationReason = recommendation.recommendationReason
        item.tmdbID = recommendation.tmdbID
        item.openLibraryID = recommendation.openLibraryID
        context.insert(item)
        recommendation.wasAdded = true
        recommendation.wasDismissed = true
    }
}

enum RecommendationMode { case standard, surpriseMe }
