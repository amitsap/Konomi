import Foundation
import SwiftData

enum SerendipityLevel: String, CaseIterable {
    case conservative
    case balanced
    case adventurous

    init(intensity: Double) {
        if intensity < 0.33 {
            self = .conservative
        } else if intensity < 0.66 {
            self = .balanced
        } else {
            self = .adventurous
        }
    }

    var displayName: String {
        switch self {
        case .conservative: "Familiar"
        case .balanced: "Balanced"
        case .adventurous: "Adventurous"
        }
    }

    var intensity: Double {
        switch self {
        case .conservative: 0
        case .balanced: 0.5
        case .adventurous: 1
        }
    }

    var promptGuidance: String {
        switch self {
        case .conservative:
            "Include exactly 1 serendipitous pick among the 10 recommendations."
        case .balanced:
            "Include at least 3 serendipitous picks among the 10 recommendations."
        case .adventurous:
            "Include at least 5 serendipitous picks among the 10 recommendations while preserving thematic fit with this person's taste."
        }
    }
}

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

    var serendipityLevel: SerendipityLevel {
        SerendipityLevel(intensity: serendipityIntensity)
    }
}
