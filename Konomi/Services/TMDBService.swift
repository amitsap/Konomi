import Foundation

// MARK: - Response types

struct TMDBSearchResult: Decodable, Identifiable {
    let id: Int
    let title: String?          // movies
    let name: String?           // TV shows
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIds: [Int]?

    var displayTitle: String { title ?? name ?? "Unknown" }

    var displayYear: Int? {
        let dateStr = releaseDate ?? firstAirDate ?? ""
        return Int(dateStr.prefix(4))
    }

    var coverURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: TMDBService.imageBase + path)
    }
}

struct TMDBGenre: Decodable {
    let id: Int
    let name: String
}

struct TMDBMovieDetail: Decodable {
    struct TMDBCredits: Decodable {
        struct CrewMember: Decodable {
            let name: String
            let job: String?
        }

        let crew: [CrewMember]?
    }

    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let runtime: Int?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [TMDBGenre]?
    let credits: TMDBCredits?

    var year: Int? { releaseDate.flatMap { Int($0.prefix(4)) } }
    var genreNames: [String] { genres?.map(\.name) ?? [] }
    var directorName: String {
        credits?.crew?.first(where: { ($0.job ?? "").caseInsensitiveCompare("Director") == .orderedSame })?.name ?? ""
    }
    var coverURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: TMDBService.imageBase + path)
    }
}

struct TMDBTVDetail: Decodable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?
    let numberOfSeasons: Int?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [TMDBGenre]?
    let createdBy: [TMDBCreator]?

    struct TMDBCreator: Decodable {
        let name: String
    }

    var year: Int? { firstAirDate.flatMap { Int($0.prefix(4)) } }
    var genreNames: [String] { genres?.map(\.name) ?? [] }
    var creatorName: String { createdBy?.first?.name ?? "" }
    var coverURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: TMDBService.imageBase + path)
    }
}

enum TMDBError: Error, LocalizedError {
    case noAPIKey
    case apiError(Int)
    case notFound
    case networkError(Error)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No TMDB API key configured. Add it in Settings."
        case .apiError(let code): return "TMDB API error (HTTP \(code))"
        case .notFound: return "Not found on TMDB"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .parseError: return "Could not parse TMDB response"
        }
    }
}

// MARK: - Service

enum TMDBService {
    static let imageBase = "https://image.tmdb.org/t/p/w500"
    private static let baseURL = "https://api.themoviedb.org/3"

    // MARK: Search

    static func searchMovies(query: String) async throws -> [TMDBSearchResult] {
        guard let key = KeychainService.loadTMDB() else { throw TMDBError.noAPIKey }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "\(baseURL)/search/movie?query=\(encoded)&api_key=\(key)&language=en-US&page=1")!
        return try await fetchResults(from: url)
    }

    static func searchTVShows(query: String) async throws -> [TMDBSearchResult] {
        guard let key = KeychainService.loadTMDB() else { throw TMDBError.noAPIKey }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "\(baseURL)/search/tv?query=\(encoded)&api_key=\(key)&language=en-US&page=1")!
        return try await fetchResults(from: url)
    }

    // MARK: Details

    static func fetchMovieDetails(id: Int) async throws -> TMDBMovieDetail {
        guard let key = KeychainService.loadTMDB() else { throw TMDBError.noAPIKey }
        let url = URL(string: "\(baseURL)/movie/\(id)?api_key=\(key)&language=en-US")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw TMDBError.parseError }
        if http.statusCode == 404 { throw TMDBError.notFound }
        guard http.statusCode == 200 else { throw TMDBError.apiError(http.statusCode) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TMDBMovieDetail.self, from: data)
    }

    static func fetchTVDetails(id: Int) async throws -> TMDBTVDetail {
        guard let key = KeychainService.loadTMDB() else { throw TMDBError.noAPIKey }
        let url = URL(string: "\(baseURL)/tv/\(id)?api_key=\(key)&language=en-US")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw TMDBError.parseError }
        if http.statusCode == 404 { throw TMDBError.notFound }
        guard http.statusCode == 200 else { throw TMDBError.apiError(http.statusCode) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TMDBTVDetail.self, from: data)
    }

    // MARK: - Validation

    static func validateKey(_ key: String) async throws -> Bool {
        let encoded = "test".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "\(baseURL)/search/movie?query=\(encoded)&api_key=\(key)&language=en-US&page=1")!
        let (_, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // MARK: - Helpers

    private static func fetchResults(from url: URL) async throws -> [TMDBSearchResult] {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw TMDBError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw TMDBError.parseError }
        guard http.statusCode == 200 else { throw TMDBError.apiError(http.statusCode) }

        struct SearchResponse: Decodable { let results: [TMDBSearchResult] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let parsed = try decoder.decode(SearchResponse.self, from: data)
        return parsed.results
    }
}
