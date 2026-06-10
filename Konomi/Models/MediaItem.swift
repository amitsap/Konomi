import Foundation
import SwiftData

@Model
final class MediaItem {
    var id: UUID = UUID()
    var mediaTypeRaw: String = MediaType.movie.rawValue
    var statusRaw: String = MediaStatus.wantTo.rawValue

    // Metadata
    var title: String = ""
    var originalTitle: String?
    var creator: String = ""
    var year: Int?
    var coverURLString: String?
    var coverImageData: Data?
    var synopsis: String?
    var genres: [String] = []
    var tags: [String] = []

    // External IDs
    var tmdbID: Int?
    var openLibraryID: String?
    var isbn: String?

    // Public ratings (reference only)
    var publicScore: Double?
    var publicVoteCount: Int?

    // Personal rating
    var personalScore: Int?
    var dateAdded: Date = Date()
    var dateStarted: Date?
    var dateCompleted: Date?
    var dateAbandoned: Date?

    // Personal notes
    var review: String?
    var notes: String?
    var isFavorite: Bool = false

    // AI recommendation metadata
    var recommendedByAI: Bool = false
    var serendipityScore: Double?
    var publicRatingGap: Double?
    var recommendationReason: String?

    // Media-type specific
    var runtime: Int?       // movies: minutes
    var pageCount: Int?     // books
    var seasonCount: Int?   // TV shows

    @Relationship(deleteRule: .cascade)
    var detailedRating: DetailedRating?

    init() {}

    var mediaType: MediaType {
        get { MediaType(rawValue: mediaTypeRaw) ?? .movie }
        set { mediaTypeRaw = newValue.rawValue }
    }

    var status: MediaStatus {
        get { MediaStatus(rawValue: statusRaw) ?? .wantTo }
        set { statusRaw = newValue.rawValue }
    }

    var isCompleted: Bool { status == .completed }
    var isInProgress: Bool { status == .inProgress }

    var displayScore: String {
        guard let score = personalScore else { return "—" }
        return "\(score)"
    }

    var publicDisplayScore: String {
        guard let score = publicScore else { return "—" }
        return String(format: "%.1f", score)
    }

    var coverURL: URL? {
        guard let str = coverURLString else { return nil }
        return URL(string: str)
    }
}
