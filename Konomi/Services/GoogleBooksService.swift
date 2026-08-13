import Foundation

struct GoogleBookResult: Sendable {
    let title: String
    let authors: [String]
    let description: String?
    let thumbnailURLString: String?
    let categories: [String]
    let publishedYear: Int?
    let pageCount: Int?
}

enum GoogleBooksError: Error, LocalizedError {
    case invalidResponse
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Google Books returned an invalid response."
        case .rateLimited:
            return "Google Books rate limited the request. Add an API key in Settings for higher limits."
        }
    }
}

final class GoogleBooksService: Sendable {
    private let apiKey: String?

    nonisolated init(apiKey: String?) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = trimmed?.isEmpty == false ? trimmed : nil
    }

    nonisolated func fetchBookMetadata(
        title: String,
        author: String,
        isbn: String?
    ) async throws -> GoogleBookResult? {
        var queryParts: [String] = []
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedISBN = isbn?.replacingOccurrences(of: "-", with: "")

        if let cleanedISBN, !cleanedISBN.isEmpty {
            queryParts.append("isbn:\(cleanedISBN)")
        }
        if !cleanedTitle.isEmpty {
            queryParts.append("intitle:\(cleanedTitle)")
        }
        if !cleanedAuthor.isEmpty {
            queryParts.append("inauthor:\(cleanedAuthor)")
        }

        guard !queryParts.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        components?.queryItems = [
            URLQueryItem(name: "q", value: queryParts.joined(separator: "+")),
            URLQueryItem(name: "maxResults", value: "1"),
            URLQueryItem(name: "printType", value: "books")
        ]

        if let apiKey {
            components?.queryItems?.append(URLQueryItem(name: "key", value: apiKey))
        }

        guard let url = components?.url else {
            throw GoogleBooksError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("KonomiApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GoogleBooksError.invalidResponse
        }

        if http.statusCode == 429 {
            throw GoogleBooksError.rateLimited
        }

        guard (200...299).contains(http.statusCode) else {
            throw GoogleBooksError.invalidResponse
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["items"] as? [[String: Any]],
            let first = items.first,
            let volumeInfo = first["volumeInfo"] as? [String: Any]
        else {
            return nil
        }

        let resultTitle = volumeInfo["title"] as? String ?? cleanedTitle
        let authors = volumeInfo["authors"] as? [String] ?? []
        let description = volumeInfo["description"] as? String
        let categories = volumeInfo["categories"] as? [String] ?? []
        let pageCount = volumeInfo["pageCount"] as? Int

        let publishedDate = volumeInfo["publishedDate"] as? String
        let publishedYear = publishedDate.flatMap(Self.extractYear)

        let imageLinks = volumeInfo["imageLinks"] as? [String: Any]
        let thumbnail = (imageLinks?["thumbnail"] as? String)?
            .replacingOccurrences(of: "http://", with: "https://")

        return GoogleBookResult(
            title: resultTitle,
            authors: authors,
            description: description,
            thumbnailURLString: thumbnail,
            categories: categories,
            publishedYear: publishedYear,
            pageCount: pageCount
        )
    }

    nonisolated private static func extractYear(from value: String) -> Int? {
        let digits = value.prefix(4)
        return Int(digits)
    }
}
