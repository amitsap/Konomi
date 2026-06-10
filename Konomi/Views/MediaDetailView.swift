import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MediaDetailView: View {
    @Bindable var item: MediaItem
    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]

    @State private var showDetailedRating = false
    @State private var selectedCoverPhoto: PhotosPickerItem?
    @State private var showImageImporter = false
    @State private var coverImportError: String?

    private var showPublic: Bool { settings.first?.showPublicScores ?? true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero
                heroSection

                // Score comparison
                ScoreComparisonCard(
                    personalScore: item.personalScore,
                    publicScore: item.publicScore,
                    showPublic: showPublic
                )
                .padding(.horizontal, 16)

                // Status & favorite
                statusRow
                    .padding(.horizontal, 16)

                if item.mediaType == .book {
                    readingDatesSection
                        .padding(.horizontal, 16)
                }

                // Quick rating
                ratingSection
                    .padding(.horizontal, 16)

                // Detailed rating toggle
                DisclosureGroup("Detailed Rating", isExpanded: $showDetailedRating) {
                    detailedRatingSection
                }
                .padding(.horizontal, 16)
                .tint(KonomiTheme.secondary)

                // Review
                reviewSection
                    .padding(.horizontal, 16)

                // Notes
                notesSection
                    .padding(.horizontal, 16)

                // Metadata
                if let synopsis = item.synopsis, !synopsis.isEmpty {
                    metadataSection(synopsis: synopsis)
                        .padding(.horizontal, 16)
                }

                // AI context
                if item.recommendedByAI {
                    aiContextSection
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 32)
            }
        }
        .background(KonomiTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await BookCoverService.enrichIfNeeded(for: item, in: context)
        }
        .onChange(of: selectedCoverPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                await importPickedPhoto(newValue)
            }
        }
        .fileImporter(
            isPresented: $showImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: handleImageImport(result:)
        )
        .alert("Couldn't Update Cover", isPresented: coverImportErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coverImportError ?? "Please try a different image.")
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                CoverImageView(
                    urlString: item.coverURLString,
                    cachedData: item.coverImageData,
                    mediaType: item.mediaType,
                    width: 110,
                    height: 165
                )

                Menu {
                    PhotosPicker(selection: $selectedCoverPhoto, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showImageImporter = true
                    } label: {
                        Label("Choose from Files", systemImage: "folder")
                    }

                    if item.coverImageData != nil || item.coverURLString != nil {
                        Button(role: .destructive) {
                            clearCover()
                        } label: {
                            Label("Remove Cover", systemImage: "trash")
                        }
                    }
                } label: {
                    Text(item.coverImageData != nil || item.coverURLString != nil ? "Change Cover" : "Add Cover")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KonomiTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(KonomiTheme.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .frame(width: 110)
            .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KonomiTheme.text)
                    .lineLimit(4)

                if !item.creator.isEmpty {
                    Text(item.creator)
                        .font(.subheadline)
                        .foregroundStyle(KonomiTheme.secondary)
                }

                if let year = item.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.secondary)
                }

                if !item.genres.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(item.genres.prefix(4), id: \.self) { genre in
                            Text(genre)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(KonomiTheme.secondary.opacity(0.12))
                                .foregroundStyle(KonomiTheme.secondary)
                                .clipShape(Capsule())
                        }
                    }
                }

                // Media-specific info
                HStack(spacing: 12) {
                    if let runtime = item.runtime {
                        Label(Formatters.runtime(runtime), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(KonomiTheme.secondary)
                    }
                    if let pages = item.pageCount {
                        Label("\(pages) pages", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(KonomiTheme.secondary)
                    }
                    if let seasons = item.seasonCount {
                        Label("\(seasons) seasons", systemImage: "tv")
                            .font(.caption)
                            .foregroundStyle(KonomiTheme.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(MediaStatus.allCases, id: \.self) { s in
                    Button {
                        updateStatus(s)
                    } label: {
                        Label(s.displayName, systemImage: statusIcon(s))
                    }
                }
            } label: {
                StatusBadge(status: item.status)
            }

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.2)) {
                    item.isFavorite.toggle()
                }
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(item.isFavorite ? KonomiTheme.primary : KonomiTheme.secondary)
                    .scaleEffect(item.isFavorite ? 1.15 : 1.0)
            }
        }
    }

    // MARK: - Rating

    private var readingDatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reading Dates")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KonomiTheme.secondary)

            dateRow(
                title: "Started Reading",
                dateBinding: startedReadingDateBinding,
                isSet: item.dateStarted != nil,
                onAdd: { item.dateStarted = item.dateAdded },
                onClear: { item.dateStarted = nil }
            )

            dateRow(
                title: "Finished Reading",
                dateBinding: finishedReadingDateBinding,
                isSet: item.dateCompleted != nil,
                onAdd: { item.dateCompleted = item.dateStarted ?? item.dateAdded },
                onClear: { item.dateCompleted = nil }
            )
        }
        .padding(16)
        .cardStyle()
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Rating")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KonomiTheme.secondary)
            RatingView(score: $item.personalScore)
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - Detailed rating

    private var detailedRatingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Emotional response
            VStack(alignment: .leading, spacing: 8) {
                Text("Emotional Response")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KonomiTheme.secondary)
                EmotionalResponsePicker(selected: emotionalResponsesBinding)
            }

            // Mood tags
            VStack(alignment: .leading, spacing: 8) {
                Text("Mood")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KonomiTheme.secondary)
                MoodTagGrid(selected: moodTagsBinding)
                    .padding(.horizontal, 4)
            }

            // Factors
            FactorView(label: "Would watch/read again", value: rewatchBinding)
            FactorView(label: "Would recommend", value: recommendBinding)
        }
        .padding(.top, 12)
    }

    // MARK: - Review

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Review")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KonomiTheme.secondary)
            TextEditor(text: reviewBinding)
                .font(.body)
                .frame(minHeight: 80)
                .padding(8)
                .background(KonomiTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(KonomiTheme.secondary.opacity(0.15), lineWidth: 1)
                )
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Private Notes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KonomiTheme.secondary)
            TextEditor(text: notesBinding)
                .font(.body)
                .frame(minHeight: 60)
                .padding(8)
                .background(KonomiTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(KonomiTheme.secondary.opacity(0.15), lineWidth: 1)
                )
        }
    }

    // MARK: - Metadata

    private func metadataSection(synopsis: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synopsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KonomiTheme.secondary)
            Text(synopsis)
                .font(.body)
                .foregroundStyle(KonomiTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - AI Context

    private var aiContextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(KonomiTheme.serendipity)
                Text("Claude Recommended This")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KonomiTheme.serendipity)
            }
            if let reason = item.recommendationReason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(KonomiTheme.text)
            }
            if let gap = item.serendipityScore, gap > 0.5 {
                SerendipityBadge(score: gap)
            }
        }
        .padding(16)
        .background(KonomiTheme.serendipity.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.cardRadius))
    }

    // MARK: - Helpers

    private func updateStatus(_ newStatus: MediaStatus) {
        item.status = newStatus
        switch newStatus {
        case .inProgress: if item.dateStarted == nil { item.dateStarted = Date() }
        case .completed: item.dateCompleted = Date()
        case .abandoned: item.dateAbandoned = Date()
        default: break
        }
    }

    private func statusIcon(_ s: MediaStatus) -> String {
        switch s {
        case .wantTo: return "bookmark"
        case .inProgress: return "play.circle"
        case .completed: return "checkmark.circle"
        case .abandoned: return "xmark.circle"
        }
    }

    private func dateRow(
        title: String,
        dateBinding: Binding<Date>,
        isSet: Bool,
        onAdd: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(KonomiTheme.text)
                Spacer()
                if isSet {
                    Button("Clear", role: .destructive, action: onClear)
                        .font(.caption.weight(.semibold))
                } else {
                    Button("Add Date", action: onAdd)
                        .font(.caption.weight(.semibold))
                }
            }

            if isSet {
                DatePicker(
                    "",
                    selection: dateBinding,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Not set")
                    .font(.caption)
                    .foregroundStyle(KonomiTheme.secondary)
            }
        }
    }

    @MainActor
    private func importPickedPhoto(_ photoItem: PhotosPickerItem) async {
        do {
            guard let data = try await photoItem.loadTransferable(type: Data.self) else {
                coverImportError = "The selected photo could not be loaded."
                return
            }
            try applyCoverImageData(data)
            selectedCoverPhoto = nil
        } catch {
            coverImportError = "The selected photo could not be loaded."
        }
    }

    private func handleImageImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            do {
                guard let url = urls.first else {
                    coverImportError = "No image file was selected."
                    return
                }
                guard url.startAccessingSecurityScopedResource() else {
                    coverImportError = "Konomi couldn't access that image file."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                try applyCoverImageData(data)
            } catch {
                coverImportError = "That file couldn't be used as a cover image."
            }
        case .failure:
            coverImportError = "That file couldn't be opened."
        }
    }

    private func applyCoverImageData(_ data: Data) throws {
        let normalizedData: Data
        if let image = UIImage(data: data),
           let jpegData = image.jpegData(compressionQuality: 0.9) {
            normalizedData = jpegData
        } else {
            throw NSError(domain: "MediaDetailView", code: 1)
        }

        item.coverImageData = normalizedData
        try? context.save()
    }

    private func clearCover() {
        item.coverImageData = nil
        item.coverURLString = nil
        try? context.save()
    }

    // MARK: - Bindings via DetailedRating

    private var detailedRating: DetailedRating {
        if let existing = item.detailedRating { return existing }
        let dr = DetailedRating()
        item.detailedRating = dr
        return dr
    }

    private var emotionalResponsesBinding: Binding<[EmotionalResponse]> {
        Binding(
            get: { detailedRating.emotionalResponses },
            set: { detailedRating.emotionalResponses = $0 }
        )
    }

    private var moodTagsBinding: Binding<[MoodTag]> {
        Binding(
            get: { detailedRating.moodTags },
            set: { detailedRating.moodTags = $0 }
        )
    }

    private var rewatchBinding: Binding<Int> {
        Binding(
            get: { detailedRating.rewatchFactor },
            set: { detailedRating.rewatchFactor = $0 }
        )
    }

    private var recommendBinding: Binding<Int> {
        Binding(
            get: { detailedRating.recommendFactor },
            set: { detailedRating.recommendFactor = $0 }
        )
    }

    private var reviewBinding: Binding<String> {
        Binding(
            get: { item.review ?? "" },
            set: { item.review = $0.isEmpty ? nil : $0 }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { item.notes ?? "" },
            set: { item.notes = $0.isEmpty ? nil : $0 }
        )
    }

    private var startedReadingDateBinding: Binding<Date> {
        Binding(
            get: { item.dateStarted ?? item.dateAdded },
            set: { item.dateStarted = $0 }
        )
    }

    private var finishedReadingDateBinding: Binding<Date> {
        Binding(
            get: { item.dateCompleted ?? item.dateStarted ?? item.dateAdded },
            set: { item.dateCompleted = $0 }
        )
    }

    private var coverImportErrorBinding: Binding<Bool> {
        Binding(
            get: { coverImportError != nil },
            set: { if !$0 { coverImportError = nil } }
        )
    }
}
