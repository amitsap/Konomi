import Combine
import SwiftData
import SwiftUI

@MainActor
final class QuickSetupViewModel: ObservableObject {
    @Published var selectedMediaType: MediaType = .movie
    @Published var selectedFilterIDByType: [MediaType: String] = [.movie: "all", .tvShow: "all"]
    @Published var searchText = ""
    @Published var displayedItemsByType: [MediaType: [QuickSetupItem]] = [.movie: [], .tvShow: []]
    @Published var selectedItems: [String: QuickSetupItem] = [:]
    @Published var isInitialLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var detailItem: QuickSetupItem?
    @Published var detailState: QuickSetupDetail?
    @Published var isLoadingDetail = false
    @Published var flow: QuickSetupFlow = .browse
    @Published var completionResult: QuickSetupCompletion?
    @Published var currentRatingIndex = 0
    @Published var ratingDrafts: [String: Int?] = [:]

    private let service = QuickSetupService.shared
    private var pageByKey: [String: Int] = [:]
    private var hasMoreByKey: [String: Bool] = [:]
    private var loadedKeySignature: Set<String> = []
    private var currentLoadTask: Task<Void, Never>?

    let movieFilters: [QuickSetupFilter] = [
        .init(id: "all", title: "All", kind: .all),
        .init(id: "movie-action", title: "Action", kind: .genre(28)),
        .init(id: "movie-drama", title: "Drama", kind: .genre(18)),
        .init(id: "movie-comedy", title: "Comedy", kind: .genre(35)),
        .init(id: "movie-thriller", title: "Thriller", kind: .genre(53)),
        .init(id: "movie-scifi", title: "Sci-Fi", kind: .genre(878)),
        .init(id: "movie-horror", title: "Horror", kind: .genre(27)),
        .init(id: "movie-animation", title: "Animation", kind: .genre(16)),
        .init(id: "movie-documentary", title: "Documentary", kind: .genre(99)),
        .init(id: "movie-80s", title: "80s", kind: .decade(startYear: 1980, endYear: 1989)),
        .init(id: "movie-90s", title: "90s", kind: .decade(startYear: 1990, endYear: 1999)),
        .init(id: "movie-00s", title: "00s", kind: .decade(startYear: 2000, endYear: 2009)),
        .init(id: "movie-10s", title: "10s", kind: .decade(startYear: 2010, endYear: 2019)),
        .init(id: "movie-20s", title: "20s", kind: .decade(startYear: 2020, endYear: 2029))
    ]

    let tvFilters: [QuickSetupFilter] = [
        .init(id: "all", title: "All", kind: .all),
        .init(id: "tv-drama", title: "Drama", kind: .genre(18)),
        .init(id: "tv-comedy", title: "Comedy", kind: .genre(35)),
        .init(id: "tv-crime", title: "Crime", kind: .genre(80)),
        .init(id: "tv-scifi", title: "Sci-Fi", kind: .genre(10765)),
        .init(id: "tv-fantasy", title: "Fantasy", kind: .genre(10765)),
        .init(id: "tv-documentary", title: "Documentary", kind: .genre(99)),
        .init(id: "tv-reality", title: "Reality", kind: .genre(10764)),
        .init(id: "tv-animation", title: "Animation", kind: .genre(16)),
        .init(id: "tv-mini", title: "Mini-Series", kind: .tvType(2))
    ]

    var selectedCount: Int { selectedItems.count }

    var currentFilters: [QuickSetupFilter] {
        selectedMediaType == .movie ? movieFilters : tvFilters
    }

    var currentFilter: QuickSetupFilter {
        let selectedID = selectedFilterIDByType[selectedMediaType] ?? "all"
        return currentFilters.first(where: { $0.id == selectedID }) ?? currentFilters[0]
    }

    var displayedItems: [QuickSetupItem] {
        displayedItemsByType[selectedMediaType] ?? []
    }

    var selectedVisibleCount: Int {
        displayedItems.filter { selectedItems[$0.id] != nil }.count
    }

    var hasMore: Bool {
        hasMoreByKey[currentKey] ?? true
    }

    var selectedTitles: [QuickSetupItem] {
        selectedItems.values.sorted {
            if $0.mediaType == $1.mediaType {
                return $0.title < $1.title
            }
            return $0.mediaType.rawValue < $1.mediaType.rawValue
        }
    }

    var ratingItems: [QuickSetupItem] {
        selectedTitles
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentKey: String {
        "\(selectedMediaType.rawValue)|\(currentFilter.id)|\(normalizedSearchText.lowercased())"
    }

    func onAppear() {
        guard displayedItems.isEmpty else { return }
        loadInitial()
    }

    func mediaTypeChanged() {
        if displayedItems.isEmpty {
            loadInitial()
        }
    }

    func updateSearchText(_ text: String) {
        currentLoadTask?.cancel()
        currentLoadTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.resetCurrentFeed()
                self.loadInitial()
            }
        }
    }

    func selectFilter(_ filter: QuickSetupFilter) {
        selectedFilterIDByType[selectedMediaType] = filter.id
        resetCurrentFeed()
        loadInitial()
    }

    func loadInitial() {
        let key = currentKey
        if isInitialLoading || loadedKeySignature.contains(key) && !(displayedItemsByType[selectedMediaType] ?? []).isEmpty {
            return
        }

        isInitialLoading = true
        errorMessage = nil
        pageByKey[key] = 0

        Task {
            do {
                let batch = try await service.fetchBatch(
                    mediaType: selectedMediaType,
                    filter: currentFilter,
                    batchIndex: 0,
                    searchQuery: normalizedSearchText.isEmpty ? nil : normalizedSearchText
                )
                await MainActor.run {
                    self.displayedItemsByType[self.selectedMediaType] = batch.items
                    self.hasMoreByKey[key] = batch.hasMore
                    self.loadedKeySignature.insert(key)
                    self.isInitialLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isInitialLoading = false
                }
            }
        }
    }

    func loadMoreIfNeeded(for item: QuickSetupItem) {
        guard hasMore, !isInitialLoading, !isLoadingMore else { return }
        guard displayedItems.suffix(12).contains(item) else { return }

        let key = currentKey
        let nextBatch = (pageByKey[key] ?? 0) + 1
        isLoadingMore = true

        Task {
            do {
                let batch = try await service.fetchBatch(
                    mediaType: selectedMediaType,
                    filter: currentFilter,
                    batchIndex: nextBatch,
                    searchQuery: normalizedSearchText.isEmpty ? nil : normalizedSearchText
                )

                await MainActor.run {
                    let existing = self.displayedItemsByType[self.selectedMediaType] ?? []
                    let merged = existing + batch.items.filter { candidate in
                        !existing.contains(where: { $0.id == candidate.id })
                    }
                    self.displayedItemsByType[self.selectedMediaType] = merged
                    self.pageByKey[key] = nextBatch
                    self.hasMoreByKey[key] = batch.hasMore
                    self.isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMore = false
                }
            }
        }
    }

    func toggleSelection(for item: QuickSetupItem) {
        if selectedItems[item.id] != nil {
            selectedItems.removeValue(forKey: item.id)
        } else {
            selectedItems[item.id] = item
        }
    }

    func selectAllVisible() {
        for item in displayedItems {
            selectedItems[item.id] = item
        }
    }

    func deselectVisible() {
        for item in displayedItems {
            selectedItems.removeValue(forKey: item.id)
        }
    }

    func presentDetails(for item: QuickSetupItem) {
        detailItem = item
        detailState = QuickSetupDetail(item: item)
        isLoadingDetail = true

        Task {
            do {
                let detail = try await service.fetchDetail(for: item)
                await MainActor.run {
                    self.detailState = detail
                    self.isLoadingDetail = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingDetail = false
                }
            }
        }
    }

    func beginQuickRate() {
        currentRatingIndex = 0
        flow = .rateChoice
    }

    func startRating() {
        currentRatingIndex = 0
        flow = .rating
    }

    func recordRating(_ rating: Int?) {
        guard currentRatingIndex < ratingItems.count else { return }
        let item = ratingItems[currentRatingIndex]
        ratingDrafts[item.id] = rating

        if currentRatingIndex + 1 < ratingItems.count {
            currentRatingIndex += 1
        } else {
            flow = .importing
        }
    }

    func resetAfterCompletion() {
        selectedItems = [:]
        ratingDrafts = [:]
        currentRatingIndex = 0
        completionResult = nil
        flow = .browse
    }

    func switchMediaTypeAfterCompletion() {
        selectedMediaType = selectedMediaType == .movie ? .tvShow : .movie
        resetAfterCompletion()
        if displayedItems.isEmpty {
            loadInitial()
        }
    }

    func addSelectedItems(existingItems: [MediaItem], context: ModelContext) {
        flow = .importing

        let selected = selectedTitles
        Task {
            let existingIDs = Set(existingItems.compactMap { item in
                item.mediaType == .movie || item.mediaType == .tvShow ? "\(item.mediaType.rawValue)-\((item.tmdbID ?? -1))" : nil
            })

            var addedMovies = 0
            var addedTVShows = 0
            var skipped = 0
            var rated = 0

            for item in selected {
                guard !existingIDs.contains(item.id) else {
                    skipped += 1
                    continue
                }

                let mediaItem = MediaItem()
                mediaItem.mediaType = item.mediaType
                mediaItem.title = item.title
                mediaItem.creator = item.creator
                mediaItem.year = item.year
                mediaItem.coverURLString = item.coverURLString
                mediaItem.publicScore = item.publicScore
                mediaItem.synopsis = item.synopsis.isEmpty ? nil : item.synopsis
                mediaItem.genres = item.genres
                mediaItem.tmdbID = item.tmdbID
                mediaItem.runtime = item.runtime
                mediaItem.seasonCount = item.seasonCount
                mediaItem.status = .completed
                mediaItem.dateAdded = Date()
                mediaItem.dateCompleted = Date()

                if let rating = ratingDrafts[item.id] ?? nil {
                    mediaItem.personalScore = rating
                    rated += 1
                }

                context.insert(mediaItem)

                if item.mediaType == .movie {
                    addedMovies += 1
                } else if item.mediaType == .tvShow {
                    addedTVShows += 1
                }

                Task {
                    await CoverImageService.cacheIfNeeded(for: mediaItem)
                }
            }

            try? context.save()

            await MainActor.run {
                self.completionResult = QuickSetupCompletion(
                    addedMovies: addedMovies,
                    addedTVShows: addedTVShows,
                    skipped: skipped,
                    ratedCount: rated
                )
                self.flow = .complete
            }
        }
    }

    private func resetCurrentFeed() {
        displayedItemsByType[selectedMediaType] = []
        hasMoreByKey[currentKey] = true
        loadedKeySignature.remove(currentKey)
    }
}

enum QuickSetupFlow {
    case browse
    case rateChoice
    case rating
    case importing
    case complete
}

struct QuickSetupCompletion {
    let addedMovies: Int
    let addedTVShows: Int
    let skipped: Int
    let ratedCount: Int
}

struct QuickSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppNavigationState.self) private var navigationState
    @Query(sort: \MediaItem.dateAdded, order: .reverse) private var existingItems: [MediaItem]

    @StateObject private var viewModel = QuickSetupViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            content
            if viewModel.detailItem != nil {
                detailOverlay
            }
        }
        .background(KonomiTheme.background)
        .navigationTitle("Quick Setup")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: "Search TMDB titles")
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.updateSearchText(newValue)
        }
        .onChange(of: viewModel.selectedMediaType) { _, _ in
            viewModel.mediaTypeChanged()
        }
        .task {
            viewModel.onAppear()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .principal) {
                if viewModel.selectedCount > 0 {
                    Text("\(viewModel.selectedCount) selected")
                        .font(.subheadline.weight(.semibold))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.selectedVisibleCount > 0 {
                    Button("Deselect All") {
                        viewModel.deselectVisible()
                    }
                    .font(.subheadline.weight(.semibold))
                } else {
                    Button("Select All") {
                        viewModel.selectAllVisible()
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(viewModel.displayedItems.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.flow {
        case .browse:
            browseView
        case .rateChoice:
            rateChoiceView
        case .rating:
            ratingView
        case .importing:
            importingView
        case .complete:
            completionView
        }
    }

    private var browseView: some View {
        VStack(spacing: 0) {
            Picker("Media Type", selection: $viewModel.selectedMediaType) {
                Text("Movies").tag(MediaType.movie)
                Text("TV Shows").tag(MediaType.tvShow)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            filterBar

            if let errorMessage = viewModel.errorMessage, viewModel.displayedItems.isEmpty {
                ContentUnavailableView(
                    "Couldn’t Load Titles",
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
                .frame(maxHeight: .infinity)
            } else if viewModel.isInitialLoading && viewModel.displayedItems.isEmpty {
                skeletonGrid
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.displayedItems) { item in
                            QuickSetupCard(
                                item: item,
                                isSelected: viewModel.selectedItems[item.id] != nil,
                                onTap: { viewModel.toggleSelection(for: item) },
                                onLongPress: { viewModel.presentDetails(for: item) }
                            )
                            .onAppear {
                                viewModel.loadMoreIfNeeded(for: item)
                            }
                        }

                        if viewModel.isLoadingMore {
                            ForEach(0..<3, id: \.self) { _ in
                                QuickSetupSkeletonCard()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }

            if viewModel.selectedCount > 0 {
                Button {
                    viewModel.beginQuickRate()
                } label: {
                    Text("Continue with \(viewModel.selectedCount) Selected")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(KonomiTheme.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.currentFilters) { filter in
                    Button {
                        viewModel.selectFilter(filter)
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(viewModel.currentFilter.id == filter.id ? KonomiTheme.primary : KonomiTheme.secondary.opacity(0.12))
                            .foregroundStyle(viewModel.currentFilter.id == filter.id ? .white : KonomiTheme.text)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<12, id: \.self) { _ in
                    QuickSetupSkeletonCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var rateChoiceView: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Quick Setup")
                .font(.title2.weight(.bold))
                .foregroundStyle(KonomiTheme.text)

            Text("Add \(viewModel.selectedCount) completed \(viewModel.selectedCount == 1 ? "title" : "titles") to your library.")
                .font(.body)
                .foregroundStyle(KonomiTheme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Button {
                    viewModel.addSelectedItems(existingItems: existingItems, context: context)
                } label: {
                    VStack(spacing: 4) {
                        Text("Add Without Rating")
                            .font(.headline)
                        Text("Fastest option")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(KonomiTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    viewModel.startRating()
                } label: {
                    VStack(spacing: 4) {
                        Text("Quick Rate Selected")
                            .font(.headline)
                        Text("Tap a score and move on")
                            .font(.caption)
                            .foregroundStyle(KonomiTheme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(KonomiTheme.card)
                    .foregroundStyle(KonomiTheme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(KonomiTheme.secondary.opacity(0.14), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)

            Button("Back") {
                viewModel.flow = .browse
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 8)

            Spacer()
        }
    }

    private var ratingView: some View {
        let item = viewModel.ratingItems[viewModel.currentRatingIndex]

        return VStack(spacing: 20) {
            Text("Rating \(viewModel.currentRatingIndex + 1) of \(viewModel.ratingItems.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KonomiTheme.secondary)
                .padding(.top, 16)

            AsyncImage(url: URL(string: item.coverURLString ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: 14)
                        .fill(KonomiTheme.secondary.opacity(0.15))
                        .overlay(Image(systemName: item.mediaType.icon).foregroundStyle(KonomiTheme.secondary))
                }
            }
            .frame(width: 180, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

            VStack(spacing: 6) {
                Text(item.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(KonomiTheme.text)
                Text(item.creator.isEmpty ? (item.year.map(String.init) ?? "") : item.creator)
                    .font(.subheadline)
                    .foregroundStyle(KonomiTheme.secondary)
            }
            .padding(.horizontal, 24)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(1...10, id: \.self) { score in
                    Button {
                        viewModel.recordRating(score)
                    } label: {
                        Text("\(score)")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(scoreBackground(score))
                            .foregroundStyle(score > 6 ? .white : KonomiTheme.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 16)

            Button("Skip") {
                viewModel.recordRating(nil)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(KonomiTheme.secondary)

            Spacer()
        }
    }

    private var importingView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Adding your selected titles...")
                .font(.headline)
                .foregroundStyle(KonomiTheme.text)
            Text("This may take a moment while covers cache in the background.")
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    @ViewBuilder
    private var completionView: some View {
        if let result = viewModel.completionResult {
            VStack(spacing: 18) {
                Spacer()

                Text("Quick Setup Complete")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KonomiTheme.text)

                Text("Added \(result.addedMovies) movies and \(result.addedTVShows) TV shows")
                    .font(.headline)
                    .foregroundStyle(KonomiTheme.text)

                Text("Skipped \(result.skipped) already in your library. Rate them anytime from your library.")
                    .font(.subheadline)
                    .foregroundStyle(KonomiTheme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("View Library")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(KonomiTheme.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    if shouldShowSwitchTypeButton(result: result) {
                        Button {
                            viewModel.switchMediaTypeAfterCompletion()
                        } label: {
                            Text(viewModel.selectedMediaType == .movie ? "Switch to TV Shows" : "Switch to Movies")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(KonomiTheme.card)
                                .foregroundStyle(KonomiTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(KonomiTheme.secondary.opacity(0.14), lineWidth: 1)
                                )
                        }
                    }

                    if totalRatedLibraryCount(result: result) >= 10 {
                        Button {
                            navigationState.selectedTab = .profile
                            dismiss()
                        } label: {
                            Text("Generate Taste Profile")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(KonomiTheme.primary)
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    private var detailOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.detailItem = nil
                    viewModel.detailState = nil
                }

            if let detail = viewModel.detailState {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        AsyncImage(url: URL(string: detail.item.coverURLString ?? "")) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(KonomiTheme.secondary.opacity(0.18))
                                    .overlay(Image(systemName: detail.item.mediaType.icon).foregroundStyle(KonomiTheme.secondary))
                            }
                        }
                        .frame(width: 100, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(detail.item.title)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(KonomiTheme.text)
                            if let year = detail.item.year {
                                Text(String(year))
                                    .font(.caption)
                                    .foregroundStyle(KonomiTheme.secondary)
                            }
                            if !detail.item.creator.isEmpty {
                                Text(detail.item.creator)
                                    .font(.subheadline)
                                    .foregroundStyle(KonomiTheme.secondary)
                            }
                            if let score = detail.item.publicScore {
                                Text("Public: \(Formatters.publicScore(score))")
                                    .font(.caption)
                                    .foregroundStyle(KonomiTheme.secondary.opacity(0.85))
                            }
                            FlowLayout(spacing: 6) {
                                ForEach(detail.item.genres.prefix(4), id: \.self) { genre in
                                    Text(genre)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(KonomiTheme.secondary.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    if viewModel.isLoadingDetail {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if !detail.item.synopsis.isEmpty {
                        Text(detail.item.synopsis)
                            .font(.subheadline)
                            .foregroundStyle(KonomiTheme.text)
                            .lineLimit(2)
                    }

                    Button {
                        viewModel.toggleSelection(for: detail.item)
                    } label: {
                        Text(viewModel.selectedItems[detail.item.id] != nil ? "Deselect" : "Select")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(KonomiTheme.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(18)
                .frame(maxWidth: 360)
                .background(KonomiTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
                .padding(.horizontal, 20)
            }
        }
    }

    private func totalRatedLibraryCount(result: QuickSetupCompletion) -> Int {
        existingItems.filter { $0.personalScore != nil }.count + result.ratedCount
    }

    private func shouldShowSwitchTypeButton(result: QuickSetupCompletion) -> Bool {
        (result.addedMovies > 0 && result.addedTVShows == 0) || (result.addedTVShows > 0 && result.addedMovies == 0)
    }

    private func scoreBackground(_ score: Int) -> some ShapeStyle {
        if score >= 8 {
            return AnyShapeStyle(KonomiTheme.primary)
        }
        if score >= 6 {
            return AnyShapeStyle(Color(hex: "#FFB457"))
        }
        return AnyShapeStyle(KonomiTheme.secondary.opacity(0.12))
    }
}

private struct QuickSetupCard: View {
    let item: QuickSetupItem
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: item.coverURLString ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            RoundedRectangle(cornerRadius: KonomiTheme.coverRadius)
                                .fill(KonomiTheme.secondary.opacity(0.14))
                                .overlay(Image(systemName: item.mediaType.icon).foregroundStyle(KonomiTheme.secondary))
                        }
                    }
                    .frame(height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.coverRadius))

                    if isSelected {
                        RoundedRectangle(cornerRadius: KonomiTheme.coverRadius)
                            .fill(Color.black.opacity(0.42))
                            .overlay(
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                            )
                    }
                }

                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KonomiTheme.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    onLongPress()
                }
        )
    }
}

private struct QuickSetupSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: KonomiTheme.coverRadius)
                .fill(KonomiTheme.secondary.opacity(0.14))
                .frame(height: 168)
                .overlay(
                    RoundedRectangle(cornerRadius: KonomiTheme.coverRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            RoundedRectangle(cornerRadius: 4)
                .fill(KonomiTheme.secondary.opacity(0.14))
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 4)
                .fill(KonomiTheme.secondary.opacity(0.1))
                .frame(width: 60, height: 12)
        }
    }
}
