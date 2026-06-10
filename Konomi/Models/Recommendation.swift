import Foundation
import SwiftData

@Model
final class Recommendation {
    var id: UUID = UUID()
    var mediaTypeRaw: String = MediaType.movie.rawValue
    var title: String = ""
    var creator: String = ""
    var year: Int?
    var coverURLString: String?
    var coverImageData: Data?
    var synopsis: String?
    var genres: [String] = []
    var publicScore: Double?
    var predictedPersonalScore: Double = 0
    var serendipityScore: Double = 0    // 0–1
    var recommendationReason: String = ""
    var serendipityExplanation: String?
    var isSerendipitous: Bool = false
    var generatedDate: Date = Date()
    var wasAdded: Bool = false
    var wasDismissed: Bool = false
    var tmdbID: Int?
    var openLibraryID: String?

    init() {}

    var mediaType: MediaType {
        get { MediaType(rawValue: mediaTypeRaw) ?? .movie }
        set { mediaTypeRaw = newValue.rawValue }
    }

    var predictedScoreDisplay: String {
        String(format: "%.1f", predictedPersonalScore)
    }

    var publicScoreDisplay: String {
        guard let score = publicScore else { return "—" }
        return String(format: "%.1f", score)
    }

    var serendipityPercent: Int {
        Int(serendipityScore * 100)
    }

    var coverURL: URL? {
        guard let str = coverURLString else { return nil }
        return URL(string: str)
    }
}
