import Foundation
import SwiftData

@Model
final class TasteProfile {
    var id: UUID = UUID()
    var lastUpdated: Date = Date()
    var tasteDescription: String = ""
    var favoriteGenres: [String] = []
    var favoriteCreators: [String] = []
    var favoriteThemes: [String] = []
    var avoidPatterns: [String] = []
    var strongPatterns: [String] = []
    var averagePersonalScore: Double = 0
    var totalCompleted: Int = 0

    init() {}

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > 7 * 24 * 3600 // older than 7 days
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }
}
