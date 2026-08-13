import SwiftUI
import SwiftData
import UIKit

struct RecommendationsView: View {
    @Environment(TasteAnalysisService.self) private var tasteService
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Recommendation.generatedDate, order: .reverse)
    private var recommendations: [Recommendation]

    @Query(filter: #Predicate<MediaItem> { $0.statusRaw == "completed" })
    private var completedItems: [MediaItem]

    @Query private var tasteProfiles: [TasteProfile]
    @Query private var settings: [AppSettings]

    @State private var mode: RecommendationMode = .standard
    @State private var selectedType: MediaType?
    @State private var generationStatus: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var dismissalNotice: RecommendationDismissalNotice?

    private var activeRecommendations: [Recommendation] {
        recommendations.filter { !$0.wasDismissed }
    }

    private var focusedActiveRecommendations: [Recommendation] {
        guard let selectedType else { return activeRecommendations }
        return activeRecommendations.filter { $0.mediaType == selectedType }
    }

    private var dismissedRecommendationIDs: Set<UUID> {
        Set(recommendations.filter(\.wasDismissed).map(\.id))
    }

    private var validDismissalNotice: RecommendationDismissalNotice? {
        guard let dismissalNotice,
              dismissedRecommendationIDs.contains(dismissalNotice.recommendationID) else {
            return nil
        }
        return dismissalNotice
    }

    private var dismissalExpiryKey: RecommendationUndoExpiryKey {
        RecommendationUndoExpiryKey(
            token: dismissalNotice?.token,
            isVoiceOverEnabled: isVoiceOverEnabled,
            isSwitchControlEnabled: isSwitchControlEnabled,
            isUntimed: dismissalNotice?.isUntimed ?? false
        )
    }

    private var noticeTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private var recommendationTransition: AnyTransition {
        reduceMotion ? .opacity : .scale.combined(with: .opacity)
    }

    private var displayedRecs: [Recommendation] {
        switch mode {
        case .standard:
            return focusedActiveRecommendations.filter {
                !$0.isSerendipitous || focusedActiveRecommendations.count < 5
            }
        case .surpriseMe:
            return focusedActiveRecommendations.filter(\.isSerendipitous)
        }
    }

    private var ratedCompletedCount: Int { completedItems.filter { $0.personalScore != nil }.count }
    private var canGenerate: Bool { ratedCompletedCount >= TasteAnalysisService.minimumRatedItems }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                Picker("Mode", selection: $mode) {
                    Text("For You").tag(RecommendationMode.standard)
                    Text("Surprise Me").tag(RecommendationMode.surpriseMe)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                recommendationTypePicker

                if mode == .surpriseMe {
                    surpriseBanner
                }

                if displayedRecs.isEmpty, let generationStatus {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(generationStatus)
                            .font(.subheadline)
                            .foregroundStyle(KonomiTheme.inkSecondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if !displayedRecs.isEmpty {
                    recommendationsList
                } else if !canGenerate {
                    ContentUnavailableView {
                        Label("Not Enough Data", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Rate \(max(0, TasteAnalysisService.minimumRatedItems - ratedCompletedCount)) more completed items to unlock recommendations")
                    } actions: {
                        Button("Open Library") {
                            navigationState.selectedTab = .library
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    generatePrompt
                }
            }
            .background(KonomiTheme.canvas)
            .safeAreaInset(edge: .bottom) {
                if let notice = validDismissalNotice {
                    UndoNoticeView(
                        systemImage: "xmark.circle.fill",
                        message: "Dismissed “\(notice.title)”",
                        messageAccessibilityLabel: "Dismissed \(notice.title)",
                        actionAccessibilityLabel: "Undo dismissal of \(notice.title)",
                        onUndo: restoreDismissedRecommendation
                    )
                    .transition(noticeTransition)
                }
            }
            .animation(
                reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.25),
                value: dismissalNotice?.token
            )
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await generateRecommendations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(generationStatus != nil || tasteService.isGenerating || !canGenerate)
                    .accessibilityLabel(refreshAccessibilityLabel)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Something went wrong")
            }
            .task(id: dismissalExpiryKey) {
                await expireDismissalNoticeIfNeeded()
            }
            .onChange(of: dismissedRecommendationIDs) { _, dismissedIDs in
                guard let notice = dismissalNotice,
                      !dismissedIDs.contains(notice.recommendationID) else {
                    return
                }
                withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                    dismissalNotice = nil
                }
            }
        }
    }

    // MARK: - Subviews

    private var recommendationTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                recommendationTypeButton(type: nil, label: "All", icon: "rectangle.stack")
                ForEach(MediaType.allCases, id: \.self) { type in
                    recommendationTypeButton(type: type, label: type.pluralName, icon: type.icon)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recommendation type")
    }

    private func recommendationTypeButton(type: MediaType?, label: String, icon: String) -> some View {
        let isSelected = selectedType == type
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                selectedType = type
            }
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? KonomiTheme.persimmon : KonomiTheme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(isSelected ? KonomiTheme.persimmon.opacity(0.12) : KonomiTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? KonomiTheme.persimmon.opacity(0.4) : KonomiTheme.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var surpriseBanner: some View {
        HStack(spacing: 8) {
            Text("🎲")
            Text("Ignoring the crowd — finding your hidden gems")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KonomiTheme.tasteViolet)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(KonomiTheme.tasteViolet.opacity(0.08))
    }

    private var generatePrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: mode == .surpriseMe ? "dice" : "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(mode == .surpriseMe ? KonomiTheme.tasteViolet : KonomiTheme.persimmon)
            Text(generateHeadline)
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
            Button {
                Task { await generateRecommendations() }
            } label: {
                Label(generateButtonLabel, systemImage: "sparkles")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(mode == .surpriseMe ? KonomiTheme.tasteViolet : KonomiTheme.persimmon)
                    .foregroundStyle(KonomiTheme.onPersimmon)
                    .clipShape(Capsule())
            }
            .disabled(generationStatus != nil || tasteService.isGenerating)
        }
        .frame(maxHeight: .infinity)
    }

    private var recommendationsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let generationStatus {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(generationStatus)
                            .font(.subheadline)
                            .foregroundStyle(KonomiTheme.inkSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .accessibilityElement(children: .combine)
                }

                ForEach(displayedRecs) { rec in
                    RecommendationCard(
                        recommendation: rec,
                        surpriseMode: mode == .surpriseMe,
                        showPublic: settings.first?.showPublicScores ?? true,
                        onDismiss: { dismiss(rec) }
                    )
                        .padding(.horizontal, 16)
                        .transition(recommendationTransition)
                }
            }
            .padding(.vertical, 16)
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: displayedRecs.map(\.id))
        }
    }

    // MARK: - Actions

    private var generateHeadline: String {
        if !recommendations.isEmpty, let selectedType {
            return "No \(selectedType.displayName.lowercased()) picks in this set"
        }
        return switch selectedType {
        case nil: "Across shelves and screens"
        case .book: "Your taste, in print"
        case .movie: "Your taste, on film"
        case .tvShow: "Your taste, episode by episode"
        }
    }

    private var generateButtonLabel: String {
        guard let selectedType else { return "Generate Recommendations" }
        return "Generate \(selectedType.displayName) Recommendations"
    }

    private var refreshAccessibilityLabel: String {
        guard let selectedType else { return "Refresh recommendations" }
        return "Refresh \(selectedType.displayName.lowercased()) recommendations"
    }

    private func loadingCopy(for mediaType: MediaType?) -> String {
        guard let mediaType else { return "Finding new recommendations…" }
        return "Finding new \(mediaType.displayName.lowercased()) recommendations…"
    }

    private func dismiss(_ recommendation: Recommendation) {
        let title = recommendation.title
        do {
            try RecommendationDismissalStore.dismiss(recommendation, in: context)
            let notice = RecommendationDismissalNotice(
                recommendationID: recommendation.id,
                title: title
            )
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                dismissalNotice = notice
            }
            UIAccessibility.post(
                notification: .announcement,
                argument: "Dismissed \(title). Undo available."
            )
        } catch {
            errorMessage = "Konomi couldn't dismiss \(title). Your earlier changes were left intact."
            showError = true
        }
    }

    private func restoreDismissedRecommendation() {
        guard let notice = validDismissalNotice else {
            dismissalNotice = nil
            return
        }

        do {
            _ = try RecommendationDismissalStore.restore(
                id: notice.recommendationID,
                in: context
            )
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                dismissalNotice = nil
            }
        } catch {
            if dismissalNotice?.token == notice.token {
                dismissalNotice?.isUntimed = true
            }
            errorMessage = "Konomi couldn't restore \(notice.title). Undo is still available; try again."
            showError = true
        }
    }

    private func expireDismissalNoticeIfNeeded() async {
        guard let notice = validDismissalNotice,
              !isVoiceOverEnabled,
              !isSwitchControlEnabled,
              !notice.isUntimed else {
            return
        }

        do {
            try await Task.sleep(for: .seconds(6))
        } catch {
            return
        }
        guard !Task.isCancelled, dismissalNotice?.token == notice.token else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
            dismissalNotice = nil
        }
    }

    @MainActor
    private func generateRecommendations() async {
        guard generationStatus == nil else { return }
        let requestedType = selectedType
        let requestedSurpriseMode = mode == .surpriseMe
        let excludedRecommendations = Array(recommendations)
        generationStatus = loadingCopy(for: requestedType)
        defer { generationStatus = nil }

        let profile = tasteProfiles.sorted { $0.lastUpdated > $1.lastUpdated }.first
        var activeProfile = profile

        // Generate profile if missing or stale
        if activeProfile == nil || (activeProfile?.isStale == true) {
            do {
                let newProfile = try await tasteService.generateTasteProfile(items: Array(completedItems))
                try GeneratedContentStore.replaceTasteProfile(newProfile, in: context)
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
                mediaType: requestedType,
                excludedRecommendations: excludedRecommendations,
                serendipityLevel: settings.first?.serendipityLevel ?? .balanced,
                surpriseMode: requestedSurpriseMode
            )
            let retainedRecs = try GeneratedContentStore.replaceRecommendations(newRecs, in: context)

            // Cache covers in background
            for rec in retainedRecs {
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
    let showPublic: Bool
    let onDismiss: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            recommendationHeader

            // Why text
            Text(recommendation.recommendationReason)
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            // Serendipity explanation
            if let explanation = recommendation.serendipityExplanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(KonomiTheme.tasteViolet)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Actions
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    addButton
                    dismissButton
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        addButton
                        dismissButton
                    }

                    VStack(spacing: 10) {
                        addButton
                        dismissButton
                    }
                }
            }
        }
        .padding(16)
        .background(KonomiTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius)
                .stroke(surpriseMode ? KonomiTheme.tasteViolet.opacity(0.45) : KonomiTheme.hairline, lineWidth: 1)
        }
        .task {
            await BookCoverService.enrichIfNeeded(for: recommendation, in: context)
        }
    }

    @ViewBuilder
    private var recommendationHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                CoverImageView(
                    urlString: recommendation.coverURLString,
                    cachedData: recommendation.coverImageData,
                    mediaType: recommendation.mediaType,
                    width: 70,
                    height: 105
                )
                recommendationHeaderText
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                CoverImageView(
                    urlString: recommendation.coverURLString,
                    cachedData: recommendation.coverImageData,
                    mediaType: recommendation.mediaType,
                    width: 70,
                    height: 105
                )
                recommendationHeaderText
                Spacer()
            }
        }
    }

    private var recommendationHeaderText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recommendation.title)
                .font(.headline)
                .foregroundStyle(KonomiTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if !recommendation.creator.isEmpty {
                Text(recommendation.creator)
                    .font(.subheadline)
                    .foregroundStyle(KonomiTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            scoreLine

            if recommendation.isSerendipitous {
                SerendipityBadge(score: recommendation.serendipityScore, compact: true)
            }
        }
    }

    @ViewBuilder
    private var scoreLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                predictedScore
                estimatedPublicScore
            }
        } else {
            HStack(spacing: 8) {
                predictedScore
                estimatedPublicScore
            }
        }
    }

    private var predictedScore: some View {
        HStack(spacing: 3) {
            Text(recommendation.predictedScoreDisplay)
                .font(.title3.weight(.bold))
                .foregroundStyle(surpriseMode ? KonomiTheme.tasteViolet : KonomiTheme.persimmon)
            Text("for you")
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("For you")
        .accessibilityValue(recommendation.predictedScoreDisplay)
    }

    @ViewBuilder
    private var estimatedPublicScore: some View {
        if showPublic, let pub = recommendation.publicScore {
            Text("Estimated public \(Formatters.publicScore(pub))")
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
        }
    }

    private var addButton: some View {
        Button {
            addToLibrary()
        } label: {
            Label("Add to Library", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(surpriseMode ? KonomiTheme.tasteViolet : KonomiTheme.persimmon)
                .foregroundStyle(KonomiTheme.onPersimmon)
                .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.controlRadius))
        }
    }

    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Label("Dismiss", systemImage: "xmark")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(KonomiTheme.surfaceRaised)
                .foregroundStyle(KonomiTheme.inkSecondary)
                .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: KonomiTheme.controlRadius)
                        .stroke(KonomiTheme.hairline, lineWidth: 1)
                }
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

private struct RecommendationDismissalNotice {
    let token = UUID()
    let recommendationID: UUID
    let title: String
    var isUntimed = false
}

private struct RecommendationUndoExpiryKey: Hashable {
    let token: UUID?
    let isVoiceOverEnabled: Bool
    let isSwitchControlEnabled: Bool
    let isUntimed: Bool
}

enum RecommendationMode { case standard, surpriseMe }
