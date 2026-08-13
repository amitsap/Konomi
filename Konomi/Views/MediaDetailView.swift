import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MediaDetailView: View {
    @Bindable var item: MediaItem
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .tint(KonomiTheme.inkSecondary)

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
        .background(KonomiTheme.canvas)
        .navigationTitle(item.title)
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    coverControl
                    heroMetadata
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    coverControl
                    heroMetadata
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var coverControl: some View {
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
                    .foregroundStyle(KonomiTheme.persimmon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(KonomiTheme.persimmon.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 180 : 110, alignment: .leading)
    }

    private var heroMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(KonomiTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !item.creator.isEmpty {
                Text(item.creator)
                    .font(.subheadline)
                    .foregroundStyle(KonomiTheme.inkSecondary)
            }

            if let year = item.year {
                Text(String(year))
                    .font(.caption)
                    .foregroundStyle(KonomiTheme.inkSecondary)
            }

            if !item.genres.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(item.genres.prefix(4), id: \.self) { genre in
                        Text(genre)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(KonomiTheme.inkSecondary.opacity(0.12))
                            .foregroundStyle(KonomiTheme.inkSecondary)
                            .clipShape(Capsule())
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { mediaSpecificMetadata }
                VStack(alignment: .leading, spacing: 6) { mediaSpecificMetadata }
            }
        }
    }

    @ViewBuilder
    private var mediaSpecificMetadata: some View {
        if let runtime = item.runtime {
            Label(Formatters.runtime(runtime), systemImage: "clock")
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
        }
        if let pages = item.pageCount {
            Label("\(pages) pages", systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
        }
        if let seasons = item.seasonCount {
            Label("\(seasons) seasons", systemImage: "tv")
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
        }
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
                withAnimation(reduceMotion ? nil : .spring(duration: 0.2)) {
                    item.isFavorite.toggle()
                }
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(item.isFavorite ? KonomiTheme.persimmon : KonomiTheme.inkSecondary)
                    .scaleEffect(item.isFavorite && !reduceMotion ? 1.15 : 1.0)
            }
            .accessibilityLabel(item.isFavorite ? "Unfavorite" : "Favorite")
        }
    }

    // MARK: - Rating

    private var readingDatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reading Dates")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KonomiTheme.inkSecondary)

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
            HStack {
                Text("Your Rating")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KonomiTheme.inkSecondary)

                Spacer()

                if item.personalScore != nil {
                    Menu {
                        Button(role: .destructive) {
                            item.personalScore = nil
                        } label: {
                            Label("Remove Rating", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(KonomiTheme.inkSecondary)
                    }
                    .accessibilityLabel("Rating Options")
                }
            }

            RatingView(selectedScore: item.personalScore) { score in
                item.personalScore = score
            }
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
                    .foregroundStyle(KonomiTheme.inkSecondary)
                EmotionalResponsePicker(selected: emotionalResponsesBinding)
            }

            // Mood tags
            VStack(alignment: .leading, spacing: 8) {
                Text("Mood")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KonomiTheme.inkSecondary)
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
                .foregroundStyle(KonomiTheme.inkSecondary)
            TextEditor(text: reviewBinding)
                .font(.body)
                .frame(minHeight: 80)
                .padding(8)
                .background(KonomiTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(KonomiTheme.hairline, lineWidth: 1)
                )
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Private Notes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KonomiTheme.inkSecondary)
            TextEditor(text: notesBinding)
                .font(.body)
                .frame(minHeight: 60)
                .padding(8)
                .background(KonomiTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(KonomiTheme.hairline, lineWidth: 1)
                )
        }
    }

    // MARK: - Metadata

    private func metadataSection(synopsis: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synopsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KonomiTheme.inkSecondary)
            Text(synopsis)
                .font(.body)
                .foregroundStyle(KonomiTheme.ink)
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
                    .foregroundStyle(KonomiTheme.tasteViolet)
                Text("Claude Recommended This")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KonomiTheme.tasteViolet)
            }
            if let reason = item.recommendationReason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(KonomiTheme.ink)
            }
            if let gap = item.serendipityScore, gap > 0.5 {
                SerendipityBadge(score: gap)
            }
        }
        .padding(16)
        .background(KonomiTheme.tasteViolet.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius)
                .stroke(KonomiTheme.hairline, lineWidth: 1)
        }
    }

    // MARK: - Helpers

    private func updateStatus(_ newStatus: MediaStatus) {
        if newStatus == .completed {
            item.markCompleted()
            return
        }

        item.status = newStatus
        switch newStatus {
        case .inProgress: if item.dateStarted == nil { item.dateStarted = Date() }
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
                    .foregroundStyle(KonomiTheme.ink)
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
                    .foregroundStyle(KonomiTheme.inkSecondary)
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

    private var emotionalResponsesBinding: Binding<[EmotionalResponse]> {
        Binding(
            get: { item.detailedRating?.emotionalResponses ?? [] },
            set: { newValue in
                item.updateDetailedRating(in: context) { $0.emotionalResponses = newValue }
            }
        )
    }

    private var moodTagsBinding: Binding<[MoodTag]> {
        Binding(
            get: { item.detailedRating?.moodTags ?? [] },
            set: { newValue in
                item.updateDetailedRating(in: context) { $0.moodTags = newValue }
            }
        )
    }

    private var rewatchBinding: Binding<Int> {
        Binding(
            get: { item.detailedRating?.rewatchFactor ?? 0 },
            set: { newValue in
                item.updateDetailedRating(in: context) { $0.rewatchFactor = newValue }
            }
        )
    }

    private var recommendBinding: Binding<Int> {
        Binding(
            get: { item.detailedRating?.recommendFactor ?? 0 },
            set: { newValue in
                item.updateDetailedRating(in: context) { $0.recommendFactor = newValue }
            }
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
