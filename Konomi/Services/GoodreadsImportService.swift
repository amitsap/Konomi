import Foundation
import SwiftData

struct GoodreadsBook: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let author: String
    let isbn: String?
    let isbn13: String?
    let myRating: Int
    let averageRating: Double
    let yearPublished: Int?
    let dateRead: Date?
    let dateAdded: Date
    let exclusiveShelf: String
    let bookshelves: [String]
    let myReview: String?
    let privateNotes: String?
}

struct ImportResult: Sendable {
    let totalFound: Int
    let imported: Int
    let skipped: Int
    let failed: Int
    let coversFound: Int
}

struct GoodreadsImportProgress: Sendable {
    let completed: Int
    let total: Int
    let currentTitle: String
    let coverStatus: String
}

struct GoodreadsImportPreparationProgress: Sendable {
    let processed: Int
    let total: Int
    let status: String
}

struct GoodreadsImportPreview: Sendable {
    let candidates: [PreparedGoodreadsBook]

    var totalFound: Int { candidates.count }
    var alreadyInLibrary: Int { candidates.filter(\.isDuplicate).count }
    var newBooks: Int { importableCandidates.count }
    var booksWithCovers: Int { importableCandidates.filter(\.hasCover).count }
    var booksWithoutCovers: Int { importableCandidates.filter { !$0.hasCover }.count }
    var completedCount: Int { importableCandidates.filter { $0.status == .completed }.count }
    var inProgressCount: Int { importableCandidates.filter { $0.status == .inProgress }.count }
    var wantToReadCount: Int { importableCandidates.filter { $0.status == .wantTo }.count }
    var importableCandidates: [PreparedGoodreadsBook] { candidates.filter { !$0.isDuplicate } }
    var importedRatingsCount: Int { importableCandidates.filter { $0.personalScore != nil }.count }
}

struct PreparedGoodreadsBook: Identifiable, Sendable {
    let id = UUID()
    let source: GoodreadsBook
    let status: MediaStatus
    let personalScore: Int?
    let metadata: ResolvedBookMetadata?
    let isDuplicate: Bool

    var hasCover: Bool { metadata?.coverURLString?.isEmpty == false }
}

struct ResolvedBookMetadata: Sendable {
    let coverURLString: String?
    let description: String?
    let genres: [String]
    let publishedYear: Int?
    let pageCount: Int?
    let openLibraryID: String?
}

enum GoodreadsImportError: Error, LocalizedError {
    case unsupportedEncoding
    case invalidFormat
    case emptyImport
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            return "This CSV file uses an unsupported text encoding."
        case .invalidFormat:
            return "This file does not look like a Goodreads export. Please choose the CSV from Goodreads → Import/Export."
        case .emptyImport:
            return "No valid books were found in that CSV file."
        case .unreadableFile:
            return "Konomi couldn’t read the selected file."
        }
    }
}

@MainActor
final class GoodreadsImportService {
    private let context: ModelContext
    private let googleBooksService: GoogleBooksService

    init(
        context: ModelContext,
        googleBooksService: GoogleBooksService? = nil
    ) {
        self.context = context
        self.googleBooksService = googleBooksService ?? GoogleBooksService(apiKey: KeychainService.loadGoogleBooks())
    }

    func parseCSV(_ url: URL) throws -> [GoodreadsBook] {
        let data = try Data(contentsOf: url)
        return try Self.parseCSV(data: data)
    }

    func importBooks(
        _ books: [GoodreadsBook],
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> ImportResult {
        let preview = try await prepareImport(books) { _ in }
        return try await importPreparedBooks(preview) { update in
            progress(update.completed, update.total)
        }
    }

    func prepareImport(
        _ books: [GoodreadsBook],
        progress: @escaping @Sendable (GoodreadsImportPreparationProgress) -> Void
    ) async throws -> GoodreadsImportPreview {
        guard !books.isEmpty else { throw GoodreadsImportError.emptyImport }

        let existingBooks = try context.fetch(FetchDescriptor<MediaItem>())
            .filter { $0.mediaType == .book }
        let existingIndex = ExistingLibraryIndex(items: existingBooks)

        var prepared = Array<PreparedGoodreadsBook?>(repeating: nil, count: books.count)
        var processed = 0

        for batchStart in stride(from: 0, to: books.count, by: 6) {
            let batchEnd = min(batchStart + 6, books.count)
            let batch = Array(books[batchStart..<batchEnd].enumerated())

            let results = await withTaskGroup(of: (Int, PreparedGoodreadsBook).self) { group in
                for (offset, book) in batch {
                    let index = batchStart + offset
                    let service = googleBooksService
                    group.addTask {
                        let candidate = await Self.prepareBook(
                            book,
                            existingIndex: existingIndex,
                            googleBooksService: service
                        )
                        return (index, candidate)
                    }
                }

                var batchResults: [(Int, PreparedGoodreadsBook)] = []
                for await result in group {
                    batchResults.append(result)
                }
                return batchResults
            }

            for (index, candidate) in results {
                prepared[index] = candidate
                processed += 1
                progress(
                    GoodreadsImportPreparationProgress(
                        processed: processed,
                        total: books.count,
                        status: "Checking duplicates and finding cover art"
                    )
                )
            }
        }

        let candidates = prepared.compactMap { $0 }
        guard !candidates.isEmpty else { throw GoodreadsImportError.emptyImport }
        return GoodreadsImportPreview(candidates: candidates)
    }

    func importPreparedBooks(
        _ preview: GoodreadsImportPreview,
        progress: @escaping @Sendable (GoodreadsImportProgress) -> Void
    ) async throws -> ImportResult {
        let candidates = preview.candidates
        guard !candidates.isEmpty else { throw GoodreadsImportError.emptyImport }

        var imported = 0
        var skipped = 0
        var failed = 0
        var coversFound = 0

        for (index, candidate) in candidates.enumerated() {
            let step = index + 1

            if candidate.isDuplicate {
                mergeDuplicateDatesIfNeeded(for: candidate.source)
                skipped += 1
                progress(
                    GoodreadsImportProgress(
                        completed: step,
                        total: candidates.count,
                        currentTitle: candidate.source.title,
                        coverStatus: "Already in your library, skipping"
                    )
                )
                continue
            }

            progress(
                GoodreadsImportProgress(
                    completed: step,
                    total: candidates.count,
                    currentTitle: candidate.source.title,
                    coverStatus: candidate.hasCover ? "Fetching cover art..." : "No cover found"
                )
            )

            do {
                let item = MediaItem()
                populate(item: item, from: candidate)

                if item.coverImageData == nil,
                   let coverURLString = item.coverURLString {
                    item.coverImageData = try? await CoverImageService.fetchImageData(from: coverURLString)
                }

                if item.coverImageData != nil || item.coverURLString != nil {
                    coversFound += 1
                }

                context.insert(item)
                imported += 1

                if imported.isMultiple(of: 25) {
                    try context.save()
                }
            } catch {
                failed += 1
            }
        }

        try context.save()

        return ImportResult(
            totalFound: candidates.count,
            imported: imported,
            skipped: skipped,
            failed: failed,
            coversFound: coversFound
        )
    }

    private func populate(item: MediaItem, from candidate: PreparedGoodreadsBook) {
        let source = candidate.source
        let metadata = candidate.metadata

        item.mediaType = .book
        item.status = candidate.status
        item.title = source.title
        item.creator = source.author
        item.year = source.yearPublished ?? metadata?.publishedYear
        item.coverURLString = metadata?.coverURLString
        item.synopsis = metadata?.description
        item.genres = metadata?.genres ?? []
        item.tags = source.bookshelves
        item.openLibraryID = metadata?.openLibraryID
        item.isbn = Self.normalizedISBN(source.isbn13) ?? Self.normalizedISBN(source.isbn)
        item.publicScore = source.averageRating > 0 ? source.averageRating : nil
        item.personalScore = candidate.personalScore
        item.dateAdded = source.dateAdded
        item.pageCount = metadata?.pageCount
        item.review = source.myReview
        item.notes = source.privateNotes

        switch candidate.status {
        case .completed:
            item.dateStarted = source.dateAdded
            item.dateCompleted = source.dateRead ?? source.dateAdded
        case .inProgress:
            item.dateStarted = source.dateAdded
        case .wantTo:
            break
        case .abandoned:
            item.dateAbandoned = source.dateRead
        }
    }

    private func mergeDuplicateDatesIfNeeded(for source: GoodreadsBook) {
        guard let existing = findExistingBook(matching: source) else { return }

        let mappedStatus = Self.mapShelf(source.exclusiveShelf)

        if existing.dateStarted == nil, mappedStatus == .inProgress || mappedStatus == .completed {
            existing.dateStarted = source.dateAdded
        }

        if let dateRead = source.dateRead {
            existing.dateCompleted = dateRead
        } else if existing.dateCompleted == nil, mappedStatus == .completed {
            existing.dateCompleted = source.dateAdded
        }

        switch mappedStatus {
        case .completed:
            if existing.status == .wantTo || existing.status == .inProgress {
                existing.status = .completed
            }
        case .inProgress:
            if existing.status == .wantTo {
                existing.status = .inProgress
            }
        case .wantTo, .abandoned:
            break
        }
    }

    private func findExistingBook(matching book: GoodreadsBook) -> MediaItem? {
        let normalizedISBN13 = Self.normalizedISBN(book.isbn13)
        let normalizedISBN = Self.normalizedISBN(book.isbn)
        let normalizedTitleAuthor = Self.normalizedTitleAuthor(title: book.title, author: book.author)

        return try? context.fetch(FetchDescriptor<MediaItem>()).first(where: { item in
            guard item.mediaType == .book else { return false }

            if let itemISBN = Self.normalizedISBN(item.isbn) {
                if normalizedISBN13 == itemISBN || normalizedISBN == itemISBN {
                    return true
                }
            }

            return Self.normalizedTitleAuthor(title: item.title, author: item.creator) == normalizedTitleAuthor
        })
    }

    private static func prepareBook(
        _ book: GoodreadsBook,
        existingIndex: ExistingLibraryIndex,
        googleBooksService: GoogleBooksService
    ) async -> PreparedGoodreadsBook {
        let status = mapShelf(book.exclusiveShelf)
        let personalScore = mapRating(book.myRating)
        let isDuplicate = existingIndex.contains(book: book)

        let metadata: ResolvedBookMetadata?
        if isDuplicate {
            metadata = nil
        } else {
            metadata = await resolveMetadata(for: book, googleBooksService: googleBooksService)
        }

        return PreparedGoodreadsBook(
            source: book,
            status: status,
            personalScore: personalScore,
            metadata: metadata,
            isDuplicate: isDuplicate
        )
    }

    private static func resolveMetadata(
        for book: GoodreadsBook,
        googleBooksService: GoogleBooksService
    ) async -> ResolvedBookMetadata? {
        if let isbn13 = normalizedISBN(book.isbn13),
           let openLibrary = try? await fetchOpenLibraryMetadata(isbn13: isbn13) {
            return openLibrary
        }

        let lookupISBN = normalizedISBN(book.isbn13) ?? normalizedISBN(book.isbn)
        if let google = try? await googleBooksService.fetchBookMetadata(
            title: book.title,
            author: book.author,
            isbn: lookupISBN
        ) {
            return ResolvedBookMetadata(
                coverURLString: google.thumbnailURLString,
                description: google.description,
                genres: google.categories,
                publishedYear: google.publishedYear,
                pageCount: google.pageCount,
                openLibraryID: nil
            )
        }

        return nil
    }

    private static func fetchOpenLibraryMetadata(isbn13: String) async throws -> ResolvedBookMetadata? {
        var components = URLComponents(string: "https://openlibrary.org/api/books")
        components?.queryItems = [
            URLQueryItem(name: "bibkeys", value: "ISBN:\(isbn13)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "jscmd", value: "data")
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("KonomiApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entry = json["ISBN:\(isbn13)"] as? [String: Any]
        else {
            return nil
        }

        let description: String?
        if let string = entry["description"] as? String {
            description = string
        } else if let object = entry["description"] as? [String: Any] {
            description = object["value"] as? String
        } else {
            description = nil
        }

        let subjects = (entry["subjects"] as? [[String: Any]] ?? [])
            .compactMap { $0["name"] as? String }
        let cover = entry["cover"] as? [String: Any]
        let coverURL = (cover?["large"] as? String) ?? (cover?["medium"] as? String) ?? (cover?["small"] as? String)

        let identifiers = entry["identifiers"] as? [String: Any]
        let openLibraryID = (identifiers?["openlibrary"] as? [String])?.first

        let publishDate = entry["publish_date"] as? String
        let pageCount = entry["number_of_pages"] as? Int

        return ResolvedBookMetadata(
            coverURLString: coverURL,
            description: description,
            genres: Array(subjects.prefix(6)),
            publishedYear: publishDate.flatMap(extractYear),
            pageCount: pageCount,
            openLibraryID: openLibraryID
        )
    }

    nonisolated static func parseCSV(data: Data) throws -> [GoodreadsBook] {
        guard let text = decodedCSVText(from: data) else {
            throw GoodreadsImportError.unsupportedEncoding
        }

        let rows = parseCSVText(text)
        guard let headerRow = rows.first else {
            throw GoodreadsImportError.invalidFormat
        }

        let headerIndex = Dictionary(uniqueKeysWithValues: headerRow.enumerated().map {
            (normalizeHeader($0.element), $0.offset)
        })

        let requiredHeaders = ["title", "author", "date added", "exclusive shelf"]
        guard requiredHeaders.allSatisfy({ headerIndex[$0] != nil }) else {
            throw GoodreadsImportError.invalidFormat
        }

        let books = rows.dropFirst().compactMap { row -> GoodreadsBook? in
            func value(_ header: String) -> String {
                guard let index = headerIndex[normalizeHeader(header)], row.indices.contains(index) else {
                    return ""
                }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let title = value("Title")
            let author = value("Author")
            guard !title.isEmpty, !author.isEmpty else { return nil }

            let dateAdded = parseDate(value("Date Added")) ?? Date()

            return GoodreadsBook(
                title: title,
                author: author,
                isbn: emptyToNil(value("ISBN")),
                isbn13: emptyToNil(value("ISBN13")),
                myRating: Int(value("My Rating")) ?? 0,
                averageRating: Double(value("Average Rating")) ?? 0,
                yearPublished: Int(value("Year Published")) ?? Int(value("Original Publication Year")),
                dateRead: parseDate(value("Date Read")),
                dateAdded: dateAdded,
                exclusiveShelf: emptyToNil(value("Exclusive Shelf"))?.lowercased() ?? "read",
                bookshelves: value("Bookshelves")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty },
                myReview: emptyToNil(value("My Review")),
                privateNotes: emptyToNil(value("Private Notes"))
            )
        }

        guard !books.isEmpty else {
            throw GoodreadsImportError.emptyImport
        }

        return books
    }

    nonisolated static func parseCSVText(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false

        let scalars = Array(text.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            switch scalar {
            case "\"":
                let nextIndex = index + 1
                if isInsideQuotes, nextIndex < scalars.count, scalars[nextIndex] == "\"" {
                    currentField.append("\"")
                    index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            case "," where !isInsideQuotes:
                currentRow.append(currentField)
                currentField = ""
            case "\n" where !isInsideQuotes:
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""
            case "\r":
                break
            default:
                currentField.unicodeScalars.append(scalar)
            }

            index += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }

    nonisolated private static func decodedCSVText(from data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16LittleEndian, .utf16BigEndian, .utf16, .unicode, .isoLatin1]
        for encoding in encodings {
            if let value = String(data: data, encoding: encoding) {
                return value
            }
        }
        return nil
    }

    nonisolated private static func parseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }

        let formats = [
            "yyyy/MM/dd",
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "M/d/yyyy",
            "MMM d, yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    nonisolated private static func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func normalizeHeader(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated private static func mapShelf(_ shelf: String) -> MediaStatus {
        switch shelf {
        case "currently-reading":
            return .inProgress
        case "to-read":
            return .wantTo
        case "read":
            return .completed
        default:
            return .completed
        }
    }

    nonisolated private static func mapRating(_ rating: Int) -> Int? {
        switch rating {
        case 1: return 2
        case 2: return 4
        case 3: return 6
        case 4: return 8
        case 5: return 10
        default: return nil
        }
    }

    nonisolated private static func normalizedISBN(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
        return cleaned.isEmpty ? nil : cleaned
    }

    nonisolated private static func normalizedTitleAuthor(title: String, author: String) -> String {
        "\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(author.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    nonisolated private static func extractYear(from value: String) -> Int? {
        let digits = value.filter(\.isNumber)
        guard digits.count >= 4 else { return nil }
        return Int(String(digits.prefix(4)))
    }

    private struct ExistingLibraryIndex: Sendable {
        let isbns: Set<String>
        let titleAuthors: Set<String>

        init(items: [MediaItem]) {
            isbns = Set(items.compactMap { GoodreadsImportService.normalizedISBN($0.isbn) })
            titleAuthors = Set(items.map {
                GoodreadsImportService.normalizedTitleAuthor(title: $0.title, author: $0.creator)
            })
        }

        func contains(book: GoodreadsBook) -> Bool {
            if let isbn13 = GoodreadsImportService.normalizedISBN(book.isbn13), isbns.contains(isbn13) {
                return true
            }
            if let isbn = GoodreadsImportService.normalizedISBN(book.isbn), isbns.contains(isbn) {
                return true
            }
            let fallback = GoodreadsImportService.normalizedTitleAuthor(title: book.title, author: book.author)
            return titleAuthors.contains(fallback)
        }
    }
}
