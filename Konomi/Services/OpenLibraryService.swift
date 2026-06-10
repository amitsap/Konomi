import Foundation

// MARK: - Response types

struct OLSearchResult: Identifiable {
    let id: String       // "/works/OL123W"
    let title: String
    let authorName: [String]?
    let firstPublishYear: Int?
    let coverI: Int?
    let numberOfPagesMedian: Int?
    let subjects: [String]?

    var primaryAuthor: String { authorName?.first ?? "" }
    var coverURL: URL? {
        guard let coverId = coverI else { return nil }
        return URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-M.jpg")
    }
    var genres: [String] {
        Array((subjects ?? []).prefix(5))
    }
}

struct OLBookDetail {
    let key: String
    let title: String
    let description: String?
    let subjects: [String]?
    let firstPublishDate: String?
}

enum OLError: Error, LocalizedError {
    case networkError(Error)
    case parseError
    case notFound

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .parseError: return "Could not parse Open Library response"
        case .notFound: return "Book not found on Open Library"
        }
    }
}

// MARK: - Service

enum OpenLibraryService {
    private static let baseURL = "https://openlibrary.org"

    static func searchBooks(query: String) async throws -> [OLSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(baseURL)/search.json?q=\(encoded)&fields=key,title,author_name,first_publish_year,cover_i,number_of_pages_median,subject&limit=20") else {
            throw OLError.parseError
        }

        var request = URLRequest(url: url)
        request.setValue("KonomiApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OLError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OLError.parseError
        }

        return try parseSearchResults(from: data)
    }

    static func fetchBookDetails(key: String) async throws -> OLBookDetail {
        let cleanKey = key.hasPrefix("/") ? key : "/\(key)"
        guard let url = URL(string: "\(baseURL)\(cleanKey).json") else {
            throw OLError.parseError
        }

        var request = URLRequest(url: url)
        request.setValue("KonomiApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OLError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw OLError.parseError }
        if http.statusCode == 404 { throw OLError.notFound }
        guard http.statusCode == 200 else { throw OLError.parseError }

        return try parseBookDetail(key: key, from: data)
    }

    // MARK: - Parsers

    private static func parseSearchResults(from data: Data) throws -> [OLSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]] else {
            throw OLError.parseError
        }

        return docs.compactMap { doc -> OLSearchResult? in
            guard let key = doc["key"] as? String,
                  let title = doc["title"] as? String else { return nil }

            let authorName = doc["author_name"] as? [String]
            let firstPublishYear = doc["first_publish_year"] as? Int
            let coverI = doc["cover_i"] as? Int
            let pageCount = doc["number_of_pages_median"] as? Int
            let subjects = doc["subject"] as? [String]

            return OLSearchResult(
                id: key,
                title: title,
                authorName: authorName,
                firstPublishYear: firstPublishYear,
                coverI: coverI,
                numberOfPagesMedian: pageCount,
                subjects: subjects
            )
        }
    }

    private static func parseBookDetail(key: String, from data: Data) throws -> OLBookDetail {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OLError.parseError
        }

        let title = json["title"] as? String ?? ""
        let subjects = json["subjects"] as? [String]
        let firstPublishDate = json["first_publish_date"] as? String

        // Description can be a string or an object with "value"
        var description: String?
        if let descStr = json["description"] as? String {
            description = descStr
        } else if let descObj = json["description"] as? [String: Any],
                  let value = descObj["value"] as? String {
            description = value
        }

        return OLBookDetail(
            key: key,
            title: title,
            description: description,
            subjects: subjects,
            firstPublishDate: firstPublishDate
        )
    }
}
