import Foundation
import SwiftData

@Model
final class AppSettings {
    var id: UUID = UUID()
    var showPublicScores: Bool = true
    var defaultMediaTypeRaw: String = MediaType.movie.rawValue
    var serendipityIntensity: Double = 0.5  // 0 = conservative, 1 = adventurous
    var avoidGenres: [String] = []
    var hasSeenOnboarding: Bool = false

    init() {}

    var defaultMediaType: MediaType {
        get { MediaType(rawValue: defaultMediaTypeRaw) ?? .movie }
        set { defaultMediaTypeRaw = newValue.rawValue }
    }
}
