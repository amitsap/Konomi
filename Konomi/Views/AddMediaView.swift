import SwiftUI
import SwiftData

// Unified search result bridging TMDB + Open Library
struct SearchResultItem: Identifiable {
    let id: String
    let title: String
    let creator: String
    let year: Int?
    let coverURLString: String?
    let publicScore: Double?
    let mediaType: MediaType
    let synopsis: String?
    let genres: [String]
    var tmdbID: Int? = nil
    var openLibraryID: String? = nil
    var runtime: Int? = nil
    var pageCount: Int? = nil
    var seasonCount: Int? = nil
}

struct AddMediaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var mediaType: MediaType = .movie
    @State private var searchText = ""
    @State private var results: [SearchResultItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedResult: SearchResultItem?
    @State private var showManualEntry = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Media Type", selection: $mediaType) {
                    ForEach(MediaType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(16)

                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        "Search Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .frame(maxHeight: .infinity)
                } else if results.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or add manually")
                    )
                    .frame(maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "Search for \(mediaType.pluralName)",
                        systemImage: mediaType.icon,
                        description: Text("Type to search \(mediaType == .book ? "Open Library" : "TMDB")")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List(results) { result in
                        SearchResultRow(result: result)
                            .onTapGesture { selectedResult = result }
                    }
                    .listStyle(.plain)
                }
            }
            .background(KonomiTheme.background)
            .navigationTitle("Add \(mediaType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Manually") { showManualEntry = true }
                        .font(.subheadline)
                }
            }
            .searchable(text: $searchText, prompt: "Search \(mediaType.pluralName.lowercased())...")
            .onChange(of: searchText) { _, newValue in
                scheduleSearch(query: newValue)
            }
            .onChange(of: mediaType) { _, _ in
                results = []
                if !searchText.isEmpty { scheduleSearch(query: searchText) }
            }
            .sheet(item: $selectedResult) { result in
                AddConfirmSheet(result: result) {
                    dismiss()
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualEntryView(defaultMediaType: mediaType) {
                    dismiss()
                }
            }
        }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    @MainActor
    private func performSearch(query: String) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            switch mediaType {
            case .movie:
                let tmdbResults = try await TMDBService.searchMovies(query: query)
                results = tmdbResults.map { r in
                    SearchResultItem(
                        id: "tmdb-\(r.id)",
                        title: r.displayTitle,
                        creator: "",
                        year: r.displayYear,
                        coverURLString: r.coverURL?.absoluteString,
                        publicScore: r.voteAverage,
                        mediaType: .movie,
                        synopsis: r.overview,
                        genres: [],
                        tmdbID: r.id
                    )
                }
            case .tvShow:
                let tmdbResults = try await TMDBService.searchTVShows(query: query)
                results = tmdbResults.map { r in
                    SearchResultItem(
                        id: "tmdb-tv-\(r.id)",
                        title: r.displayTitle,
                        creator: "",
                        year: r.displayYear,
                        coverURLString: r.coverURL?.absoluteString,
                        publicScore: r.voteAverage,
                        mediaType: .tvShow,
                        synopsis: r.overview,
                        genres: [],
                        tmdbID: r.id
                    )
                }
            case .book:
                let olResults = try await OpenLibraryService.searchBooks(query: query)
                results = olResults.map { r in
                    SearchResultItem(
                        id: "ol-\(r.id)",
                        title: r.title,
                        creator: r.primaryAuthor,
                        year: r.firstPublishYear,
                        coverURLString: r.coverURL?.absoluteString,
                        publicScore: nil,
                        mediaType: .book,
                        synopsis: nil,
                        genres: r.genres,
                        openLibraryID: r.id,
                        pageCount: r.numberOfPagesMedian
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Search result row

struct SearchResultRow: View {
    let result: SearchResultItem

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(
                urlString: result.coverURLString,
                cachedData: nil,
                mediaType: result.mediaType,
                width: 50,
                height: 75
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(KonomiTheme.text)
                if !result.creator.isEmpty {
                    Text(result.creator)
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.secondary)
                }
                HStack(spacing: 8) {
                    if let year = result.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(KonomiTheme.secondary)
                    }
                    // Public score — de-emphasised
                    if let score = result.publicScore {
                        Text("Public: \(Formatters.publicScore(score))")
                            .font(.caption)
                            .foregroundStyle(KonomiTheme.secondary.opacity(0.7))
                    }
                }
            }
            Spacer()
            Image(systemName: "plus.circle")
                .foregroundStyle(KonomiTheme.primary)
        }
    }
}

// MARK: - Add confirmation sheet

struct AddConfirmSheet: View {
    let result: SearchResultItem
    let onAdd: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var status: MediaStatus = .wantTo
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    CoverImageView(
                        urlString: result.coverURLString,
                        cachedData: nil,
                        mediaType: result.mediaType,
                        width: 80,
                        height: 120
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.title)
                            .font(.headline)
                            .foregroundStyle(KonomiTheme.text)
                        if !result.creator.isEmpty {
                            Text(result.creator)
                                .font(.subheadline)
                                .foregroundStyle(KonomiTheme.secondary)
                        }
                        if let year = result.year {
                            Text(String(year))
                                .font(.caption)
                                .foregroundStyle(KonomiTheme.secondary)
                        }
                        if let score = result.publicScore {
                            Text("Public: \(Formatters.publicScore(score))")
                                .font(.caption)
                                .foregroundStyle(KonomiTheme.secondary.opacity(0.7))
                        }
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KonomiTheme.secondary)
                    Picker("Status", selection: $status) {
                        ForEach(MediaStatus.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    addToLibrary()
                } label: {
                    Label("Add to Library", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(KonomiTheme.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isAdding)

                Spacer()
            }
            .padding(20)
            .background(KonomiTheme.background)
            .navigationTitle("Add to Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addToLibrary() {
        let item = MediaItem()
        item.title = result.title
        item.creator = result.creator
        item.year = result.year
        item.coverURLString = result.coverURLString
        item.publicScore = result.publicScore
        item.mediaType = result.mediaType
        item.status = status
        item.synopsis = result.synopsis
        item.genres = result.genres
        item.tmdbID = result.tmdbID
        item.openLibraryID = result.openLibraryID
        item.pageCount = result.pageCount
        item.seasonCount = result.seasonCount
        item.runtime = result.runtime
        item.dateAdded = Date()

        if status == .inProgress { item.dateStarted = Date() }
        if status == .completed { item.dateCompleted = Date() }

        context.insert(item)

        Task {
            await CoverImageService.cacheIfNeeded(for: item)
        }

        dismiss()
        onAdd()
    }
}

// MARK: - Manual entry

struct ManualEntryView: View {
    let defaultMediaType: MediaType
    let onAdd: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var creator = ""
    @State private var year = ""
    @State private var mediaType: MediaType
    @State private var status: MediaStatus = .wantTo

    init(defaultMediaType: MediaType, onAdd: @escaping () -> Void) {
        self.defaultMediaType = defaultMediaType
        self.onAdd = onAdd
        _mediaType = State(initialValue: defaultMediaType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Author / Director / Creator", text: $creator)
                    TextField("Year", text: $year)
                        .keyboardType(.numberPad)
                }
                Section("Type & Status") {
                    Picker("Type", selection: $mediaType) {
                        ForEach(MediaType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(MediaStatus.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                }
            }
            .navigationTitle("Add Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        addManually()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addManually() {
        let item = MediaItem()
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.creator = creator.trimmingCharacters(in: .whitespaces)
        item.year = Int(year)
        item.mediaType = mediaType
        item.status = status
        item.dateAdded = Date()
        if status == .inProgress { item.dateStarted = Date() }
        if status == .completed { item.dateCompleted = Date() }
        context.insert(item)
        dismiss()
        onAdd()
    }
}
