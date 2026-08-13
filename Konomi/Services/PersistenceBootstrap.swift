import Foundation
import SwiftData

enum PersistenceBootstrap {
    static let schema = Schema([
        MediaItem.self,
        DetailedRating.self,
        TasteProfile.self,
        Recommendation.self,
        AppSettings.self,
    ])

    static func makeContainer(configuration: ModelConfiguration? = nil) throws -> ModelContainer {
        let resolvedConfiguration = configuration
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container = try ModelContainer(
            for: schema,
            configurations: [resolvedConfiguration]
        )
        let context = container.mainContext

        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        if settings.isEmpty {
            context.insert(AppSettings())
            try context.save()
        }

        try performMaintenance(in: context)
        return container
    }

    private static func performMaintenance(in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<MediaItem>())
        let details = try context.fetch(FetchDescriptor<DetailedRating>())
        let profiles = try context.fetch(FetchDescriptor<TasteProfile>())
        let recommendations = try context.fetch(FetchDescriptor<Recommendation>())

        let attachedDetailIDs = Set(items.compactMap { $0.detailedRating?.id })
        let emptyAttachedItems = items.filter { $0.detailedRating?.isEmpty == true }
        let detailsToDelete = details.filter {
            $0.isEmpty || !attachedDetailIDs.contains($0.id)
        }

        let sortedProfiles = profiles.sorted {
            if $0.lastUpdated != $1.lastUpdated {
                return $0.lastUpdated > $1.lastUpdated
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        let sortedRecommendations = recommendations.sorted {
            if $0.generatedDate != $1.generatedDate {
                return $0.generatedDate > $1.generatedDate
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        var retainedRecommendationKeys = Set<String>()
        let recommendationsToDelete = sortedRecommendations.filter { recommendation in
            guard retainedRecommendationKeys.count < 10,
                  retainedRecommendationKeys.insert(recommendation.identityKey).inserted else {
                return true
            }
            return false
        }

        for item in emptyAttachedItems {
            item.detailedRating = nil
        }
        for detail in detailsToDelete {
            context.delete(detail)
        }
        for profile in sortedProfiles.dropFirst() {
            context.delete(profile)
        }
        for recommendation in recommendationsToDelete {
            context.delete(recommendation)
        }

        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
