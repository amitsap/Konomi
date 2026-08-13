import Foundation

struct QuickSetupItem: Identifiable, Hashable, Sendable {
    let tmdbID: Int
    let mediaType: MediaType
    let title: String
    let creator: String
    let year: Int?
    let coverURLString: String?
    let publicScore: Double?
    let voteCount: Int
    let synopsis: String
    let genreIDs: [Int]
    let genres: [String]
    let runtime: Int?
    let seasonCount: Int?

    var id: String { "\(mediaType.rawValue)-\(tmdbID)" }
}

struct QuickSetupDetail: Sendable {
    let item: QuickSetupItem
}

struct QuickSetupBatch: Sendable {
    let items: [QuickSetupItem]
    let hasMore: Bool
}

struct QuickSetupFilter: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case all
        case genre(Int)
        case decade(startYear: Int, endYear: Int)
        case tvType(Int)
    }

    let id: String
    let title: String
    let kind: Kind
}

@MainActor
final class QuickSetupService {
    static let shared = QuickSetupService()

    private let baseURL = "https://api.themoviedb.org/3"
    private var listCache: [String: [QuickSetupItem]] = [:]
    private var detailCache: [String: QuickSetupDetail] = [:]

    func fetchBatch(
        mediaType: MediaType,
        filter: QuickSetupFilter,
        batchIndex: Int,
        searchQuery: String?
    ) async throws -> QuickSetupBatch {
        let key = cacheKey(mediaType: mediaType, filter: filter, batchIndex: batchIndex, searchQuery: searchQuery)
        if let cached = listCache[key] {
            return QuickSetupBatch(items: cached, hasMore: !cached.isEmpty)
        }

        let items: [QuickSetupItem]
        if let searchQuery, !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items = try await search(mediaType: mediaType, query: searchQuery, batchIndex: batchIndex)
        } else {
            items = try await browse(mediaType: mediaType, filter: filter, batchIndex: batchIndex)
        }

        listCache[key] = items
        return QuickSetupBatch(items: items, hasMore: !items.isEmpty)
    }

    func fetchDetail(for item: QuickSetupItem) async throws -> QuickSetupDetail {
        if let cached = detailCache[item.id] {
            return cached
        }

        let detail: QuickSetupDetail
        switch item.mediaType {
        case .movie:
            let movie = try await fetchMovieDetail(id: item.tmdbID)
            detail = QuickSetupDetail(
                item: QuickSetupItem(
                    tmdbID: movie.id,
                    mediaType: .movie,
                    title: movie.title,
                    creator: movie.directorName,
                    year: movie.year,
                    coverURLString: movie.coverURL?.absoluteString ?? item.coverURLString,
                    publicScore: movie.voteAverage ?? item.publicScore,
                    voteCount: movie.voteCount ?? item.voteCount,
                    synopsis: movie.overview ?? item.synopsis,
                    genreIDs: movie.genres?.map(\.id) ?? item.genreIDs,
                    genres: movie.genreNames,
                    runtime: movie.runtime,
                    seasonCount: nil
                )
            )
        case .tvShow:
            let show = try await fetchTVDetail(id: item.tmdbID)
            detail = QuickSetupDetail(
                item: QuickSetupItem(
                    tmdbID: show.id,
                    mediaType: .tvShow,
                    title: show.name,
                    creator: show.creatorName,
                    year: show.year,
                    coverURLString: show.coverURL?.absoluteString ?? item.coverURLString,
                    publicScore: show.voteAverage ?? item.publicScore,
                    voteCount: show.voteCount ?? item.voteCount,
                    synopsis: show.overview ?? item.synopsis,
                    genreIDs: show.genres?.map(\.id) ?? item.genreIDs,
                    genres: show.genreNames,
                    runtime: nil,
                    seasonCount: show.numberOfSeasons
                )
            )
        case .book:
            throw TMDBError.notFound
        }

        detailCache[item.id] = detail
        return detail
    }

    private func browse(mediaType: MediaType, filter: QuickSetupFilter, batchIndex: Int) async throws -> [QuickSetupItem] {
        let pages = pageRange(for: batchIndex)

        switch mediaType {
        case .movie:
            switch filter.kind {
            case .all:
                return try await fetchCombinedMoviePages(pages: pages)
            case .genre(let id):
                return try await fetchDiscoverResults(mediaType: .movie, parameters: ["with_genres": "\(id)"], pages: pages)
            case .decade(let startYear, let endYear):
                return try await fetchDiscoverResults(
                    mediaType: .movie,
                    parameters: [
                        "primary_release_date.gte": "\(startYear)-01-01",
                        "primary_release_date.lte": "\(endYear)-12-31"
                    ],
                    pages: pages
                )
            case .tvType:
                return []
            }
        case .tvShow:
            switch filter.kind {
            case .all:
                return try await fetchCombinedTVPages(pages: pages)
            case .genre(let id):
                return try await fetchDiscoverResults(mediaType: .tvShow, parameters: ["with_genres": "\(id)"], pages: pages)
            case .tvType(let type):
                return try await fetchDiscoverResults(mediaType: .tvShow, parameters: ["with_type": "\(type)"], pages: pages)
            case .decade:
                return []
            }
        case .book:
            return []
        }
    }

    private func search(mediaType: MediaType, query: String, batchIndex: Int) async throws -> [QuickSetupItem] {
        let page = batchIndex + 1
        let endpoint = mediaType == .movie ? "/search/movie" : "/search/tv"
        let results = try await fetchResultPage(endpoint: endpoint, parameters: ["query": query], page: page)
        return results.map { map(result: $0, mediaType: mediaType) }
            .sorted { lhs, rhs in
                if lhs.voteCount == rhs.voteCount {
                    return lhs.publicScore ?? 0 > rhs.publicScore ?? 0
                }
                return lhs.voteCount > rhs.voteCount
            }
    }

    private func fetchCombinedMoviePages(pages: ClosedRange<Int>) async throws -> [QuickSetupItem] {
        async let topRated = fetchListResults(endpoint: "/movie/top_rated", mediaType: .movie, pages: pages)
        async let popular = fetchListResults(endpoint: "/movie/popular", mediaType: .movie, pages: pages)
        return mergeUnique(items: try await topRated + popular)
    }

    private func fetchCombinedTVPages(pages: ClosedRange<Int>) async throws -> [QuickSetupItem] {
        async let topRated = fetchListResults(endpoint: "/tv/top_rated", mediaType: .tvShow, pages: pages)
        async let popular = fetchListResults(endpoint: "/tv/popular", mediaType: .tvShow, pages: pages)
        return mergeUnique(items: try await topRated + popular)
    }

    private func fetchListResults(endpoint: String, mediaType: MediaType, pages: ClosedRange<Int>) async throws -> [QuickSetupItem] {
        var results: [TMDBSearchResult] = []
        try await withThrowingTaskGroup(of: [TMDBSearchResult].self) { group in
            for page in pages {
                group.addTask {
                    try await self.fetchResultPage(endpoint: endpoint, parameters: [:], page: page)
                }
            }
            for try await pageResults in group {
                results.append(contentsOf: pageResults)
            }
        }
        return mergeUnique(items: results.map { map(result: $0, mediaType: mediaType) })
    }

    private func fetchDiscoverResults(mediaType: MediaType, parameters: [String: String], pages: ClosedRange<Int>) async throws -> [QuickSetupItem] {
        let endpoint = mediaType == .movie ? "/discover/movie" : "/discover/tv"
        var results: [TMDBSearchResult] = []
        try await withThrowingTaskGroup(of: [TMDBSearchResult].self) { group in
            for page in pages {
                group.addTask {
                    try await self.fetchResultPage(endpoint: endpoint, parameters: parameters, page: page)
                }
            }
            for try await pageResults in group {
                results.append(contentsOf: pageResults)
            }
        }
        return mergeUnique(items: results.map { map(result: $0, mediaType: mediaType) })
    }

    private func fetchMovieDetail(id: Int) async throws -> TMDBMovieDetail {
        guard let key = KeychainService.loadTMDB() else { throw TMDBError.noAPIKey }
        let url = try makeURL(path: "/movie/\(id)", parameters: ["append_to_response": "credits", "api_key": key, "language": "en-US"])
        let data = try await performRequest(url: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TMDBMovieDetail.self, from: data)
    }

    private func fetchTVDetail(id: Int) async throws -> TMDBTVDetail {
        guard let key = KeychainService.loadTMDB() else { throw TMDBError.noAPIKey }
        let url = try makeURL(path: "/tv/\(id)", parameters: ["api_key": key, "language": "en-US"])
        let data = try await performRequest(url: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TMDBTVDetail.self, from: data)
    }

    private func fetchResultPage(endpoint: String, parameters: [String: String], page: Int) async throws -> [TMDBSearchResult] {
        guard let key = KeychainService.loadTMDB() else { throw TMDBError.noAPIKey }
        var allParameters = parameters
        allParameters["api_key"] = key
        allParameters["language"] = "en-US"
        allParameters["page"] = "\(page)"

        let url = try makeURL(path: endpoint, parameters: allParameters)
        let data = try await performRequest(url: url)

        struct SearchResponse: Decodable { let results: [TMDBSearchResult] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SearchResponse.self, from: data).results
    }

    private func performRequest(url: URL) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw TMDBError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw TMDBError.parseError }
        guard http.statusCode == 200 else { throw TMDBError.apiError(http.statusCode) }
        return data
    }

    private func makeURL(path: String, parameters: [String: String]) throws -> URL {
        guard var components = URLComponents(string: baseURL + path) else {
            throw TMDBError.parseError
        }
        components.queryItems = parameters
            .map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        guard let url = components.url else {
            throw TMDBError.parseError
        }
        return url
    }

    private func mergeUnique(items: [QuickSetupItem]) -> [QuickSetupItem] {
        var seen = Set<String>()
        return items
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.voteCount == rhs.voteCount {
                    return lhs.title < rhs.title
                }
                return lhs.voteCount > rhs.voteCount
            }
    }

    private func map(result: TMDBSearchResult, mediaType: MediaType) -> QuickSetupItem {
        QuickSetupItem(
            tmdbID: result.id,
            mediaType: mediaType,
            title: result.displayTitle,
            creator: "",
            year: result.displayYear,
            coverURLString: result.coverURL?.absoluteString,
            publicScore: result.voteAverage,
            voteCount: result.voteCount ?? 0,
            synopsis: result.overview ?? "",
            genreIDs: result.genreIds ?? [],
            genres: genreNames(for: result.genreIds ?? [], mediaType: mediaType),
            runtime: nil,
            seasonCount: nil
        )
    }

    private func pageRange(for batchIndex: Int) -> ClosedRange<Int> {
        let start = batchIndex * 5 + 1
        let end = start + 4
        return start...end
    }

    private func cacheKey(mediaType: MediaType, filter: QuickSetupFilter, batchIndex: Int, searchQuery: String?) -> String {
        "\(mediaType.rawValue)|\(filter.id)|\(batchIndex)|\(searchQuery?.lowercased() ?? "")"
    }

    private func genreNames(for ids: [Int], mediaType: MediaType) -> [String] {
        let mapping = mediaType == .movie ? Self.movieGenres : Self.tvGenres
        return ids.compactMap { mapping[$0] }
    }

    private static let movieGenres: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance",
        878: "Sci-Fi", 53: "Thriller", 10752: "War", 37: "Western"
    ]

    private static let tvGenres: [Int: String] = [
        10759: "Action & Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 10762: "Kids",
        9648: "Mystery", 10763: "News", 10764: "Reality", 10765: "Sci-Fi & Fantasy",
        10766: "Soap", 10767: "Talk", 10768: "War & Politics", 37: "Western"
    ]
}
