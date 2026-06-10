import Foundation
import SwiftData

enum BookCoverService {
    private actor LookupRegistry {
        private var inFlightKeys: Set<String> = []

        func begin(_ key: String) -> Bool {
            if inFlightKeys.contains(key) {
                return false
            }
            inFlightKeys.insert(key)
            return true
        }

        func end(_ key: String) {
            inFlightKeys.remove(key)
        }
    }

    private static let registry = LookupRegistry()

    @MainActor
    static func enrichIfNeeded(for item: MediaItem, in context: ModelContext? = nil) async {
        guard item.mediaType == .book,
              item.coverImageData == nil,
              (item.coverURLString == nil || item.coverURLString?.isEmpty == true)
        else { return }

        if let coverURL = try? await lookupCoverURL(
            title: item.title,
            author: item.creator,
            isbn: item.isbn
        ) {
            item.coverURLString = coverURL
            item.coverImageData = try? await CoverImageService.fetchImageData(from: coverURL)
            try? context?.save()
        }
    }

    @MainActor
    static func prewarmMissingCovers(
        for items: [MediaItem],
        in context: ModelContext? = nil,
        limit: Int = 24
    ) async {
        let candidates = items.filter {
            $0.mediaType == .book &&
            $0.coverImageData == nil &&
            ($0.coverURLString == nil || $0.coverURLString?.isEmpty == true)
        }

        guard !candidates.isEmpty else { return }

        for item in candidates.prefix(limit) {
            let key = cacheKey(title: item.title, author: item.creator, isbn: item.isbn)
            let shouldStart = await registry.begin(key)
            guard shouldStart else { continue }

            await enrichIfNeeded(for: item, in: context)
            await registry.end(key)
        }
    }

    @MainActor
    static func enrichIfNeeded(for recommendation: Recommendation, in context: ModelContext? = nil) async {
        guard recommendation.mediaType == .book,
              recommendation.coverImageData == nil,
              (recommendation.coverURLString == nil || recommendation.coverURLString?.isEmpty == true)
        else { return }

        if let coverURL = try? await lookupCoverURL(
            title: recommendation.title,
            author: recommendation.creator,
            isbn: nil
        ) {
            recommendation.coverURLString = coverURL
            recommendation.coverImageData = try? await CoverImageService.fetchImageData(from: coverURL)
            try? context?.save()
        }
    }

    nonisolated static func lookupCoverURL(
        title: String,
        author: String,
        isbn: String?
    ) async throws -> String? {
        if let isbn, !isbn.isEmpty {
            var components = URLComponents(string: "https://openlibrary.org/api/books")
            components?.queryItems = [
                URLQueryItem(name: "bibkeys", value: "ISBN:\(isbn)"),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "jscmd", value: "data")
            ]

            if let url = components?.url {
                var request = URLRequest(url: url)
                request.setValue("KonomiApp/1.0", forHTTPHeaderField: "User-Agent")
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let http = response as? HTTPURLResponse,
                   (200...299).contains(http.statusCode),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let entry = json["ISBN:\(isbn)"] as? [String: Any],
                   let cover = entry["cover"] as? [String: Any] {
                    let openLibraryCover = (cover["large"] as? String) ?? (cover["medium"] as? String) ?? (cover["small"] as? String)
                    if let openLibraryCover, !openLibraryCover.isEmpty {
                        return openLibraryCover
                    }
                }
            }
        }

        let query = "\(title) \(author)".trimmingCharacters(in: .whitespacesAndNewlines)
        if let result = try? await OpenLibraryService.searchBooks(query: query).first,
           let coverID = result.coverI {
            return "https://covers.openlibrary.org/b/id/\(coverID)-M.jpg"
        }

        let googleBooks = GoogleBooksService(apiKey: KeychainService.loadGoogleBooks())
        if let result = try? await googleBooks.fetchBookMetadata(title: title, author: author, isbn: isbn),
           let thumbnailURL = result.thumbnailURLString,
           !thumbnailURL.isEmpty {
            return thumbnailURL
        }

        return nil
    }

    nonisolated private static func cacheKey(title: String, author: String, isbn: String?) -> String {
        let normalizedISBN = isbn?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedISBN)|\(normalizedTitle)|\(normalizedAuthor)"
    }
}
