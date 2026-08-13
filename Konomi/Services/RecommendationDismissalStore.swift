import Foundation
import SwiftData

enum RecommendationDismissalRestoreResult: Equatable {
    case restored
    case missing
}

enum RecommendationDismissalStore {
    static func dismiss(
        _ recommendation: Recommendation,
        in context: ModelContext
    ) throws {
        if context.hasChanges {
            try context.save()
        }

        recommendation.wasDismissed = true
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func restore(
        id: UUID,
        in context: ModelContext
    ) throws -> RecommendationDismissalRestoreResult {
        if context.hasChanges {
            try context.save()
        }

        let recommendations = try context.fetch(
            FetchDescriptor<Recommendation>(predicate: #Predicate { $0.id == id })
        )
        guard let recommendation = recommendations.first else { return .missing }

        recommendation.wasDismissed = false
        do {
            try context.save()
            return .restored
        } catch {
            context.rollback()
            throw error
        }
    }
}
