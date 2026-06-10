import Foundation

enum MediaType: String, Codable, CaseIterable, Sendable {
    case book
    case movie
    case tvShow

    var displayName: String {
        switch self {
        case .book: return "Book"
        case .movie: return "Movie"
        case .tvShow: return "TV Show"
        }
    }

    var pluralName: String {
        switch self {
        case .book: return "Books"
        case .movie: return "Movies"
        case .tvShow: return "TV Shows"
        }
    }

    var icon: String {
        switch self {
        case .book: return "book"
        case .movie: return "film"
        case .tvShow: return "tv"
        }
    }

    var creatorLabel: String {
        switch self {
        case .book: return "Author"
        case .movie: return "Director"
        case .tvShow: return "Creator"
        }
    }
}

enum MediaStatus: String, Codable, CaseIterable, Sendable {
    case wantTo
    case inProgress
    case completed
    case abandoned

    var displayName: String {
        switch self {
        case .wantTo: return "Want to"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .abandoned: return "Abandoned"
        }
    }

    var actionLabel: String {
        switch self {
        case .wantTo: return "Add to Wishlist"
        case .inProgress: return "Start"
        case .completed: return "Mark Complete"
        case .abandoned: return "Abandon"
        }
    }
}

enum EmotionalResponse: String, Codable, CaseIterable, Sendable {
    case moved
    case entertained
    case inspired
    case thoughtful
    case unsettled
    case disappointed
    case bored

    var displayName: String {
        switch self {
        case .moved: return "Moved"
        case .entertained: return "Entertained"
        case .inspired: return "Inspired"
        case .thoughtful: return "Thoughtful"
        case .unsettled: return "Unsettled"
        case .disappointed: return "Disappointed"
        case .bored: return "Bored"
        }
    }

    var emoji: String {
        switch self {
        case .moved: return "😢"
        case .entertained: return "😄"
        case .inspired: return "✨"
        case .thoughtful: return "💭"
        case .unsettled: return "😰"
        case .disappointed: return "😞"
        case .bored: return "😴"
        }
    }
}

enum MoodTag: String, Codable, CaseIterable, Sendable {
    case cozy
    case intense
    case relaxing
    case challenging
    case funny
    case tearjerker
    case mindBending
    case inspiring

    var displayName: String {
        switch self {
        case .cozy: return "Cozy"
        case .intense: return "Intense"
        case .relaxing: return "Relaxing"
        case .challenging: return "Challenging"
        case .funny: return "Funny"
        case .tearjerker: return "Tearjerker"
        case .mindBending: return "Mind-Bending"
        case .inspiring: return "Inspiring"
        }
    }

    var emoji: String {
        switch self {
        case .cozy: return "☕"
        case .intense: return "⚡"
        case .relaxing: return "🌿"
        case .challenging: return "🧠"
        case .funny: return "😂"
        case .tearjerker: return "🥹"
        case .mindBending: return "🌀"
        case .inspiring: return "🚀"
        }
    }
}
