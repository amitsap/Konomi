import Foundation
import SwiftData

enum GeneratedContentStoreError: LocalizedError, Equatable {
    case emptyRecommendations

    var errorDescription: String? {
        switch self {
        case .emptyRecommendations:
            "Konomi didn't receive any usable recommendations. Your previous recommendations were kept."
        }
    }
}

enum GeneratedContentStore {
    static func replaceTasteProfile(
        _ profile: TasteProfile,
        in context: ModelContext
    ) throws {
        if context.hasChanges {
            try context.save()
        }
        let replacementContext = ModelContext(context.container)
        let existingProfiles = try replacementContext.fetch(FetchDescriptor<TasteProfile>())

        replacementContext.insert(profile)
        for existing in existingProfiles {
            replacementContext.delete(existing)
        }

        do {
            try replacementContext.save()
        } catch {
            replacementContext.rollback()
            throw error
        }
    }

    static func replaceRecommendations(
        _ candidates: [Recommendation],
        in context: ModelContext
    ) throws -> [Recommendation] {
        var seenKeys = Set<String>()
        let retained = candidates.filter { candidate in
            guard seenKeys.count < 10 else { return false }
            return seenKeys.insert(candidate.identityKey).inserted
        }
        guard !retained.isEmpty else {
            throw GeneratedContentStoreError.emptyRecommendations
        }

        if context.hasChanges {
            try context.save()
        }
        let replacementContext = ModelContext(context.container)
        let existingRecommendations = try replacementContext.fetch(FetchDescriptor<Recommendation>())

        for recommendation in retained {
            replacementContext.insert(recommendation)
        }
        for existing in existingRecommendations {
            replacementContext.delete(existing)
        }

        do {
            try replacementContext.save()
        } catch {
            replacementContext.rollback()
            throw error
        }

        do {
            let persisted = try context.fetch(FetchDescriptor<Recommendation>())
            let persistedByID = Dictionary(uniqueKeysWithValues: persisted.map { ($0.id, $0) })
            return retained.map { persistedByID[$0.id] ?? $0 }
        } catch {
            // Replacement already committed; cover caching can use the saved models directly.
            return retained
        }
    }
}
