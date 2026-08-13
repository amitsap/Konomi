import Foundation
import SwiftData
import Testing
@testable import Konomi

@MainActor
struct PersistenceHygieneTests {
    private func temporaryStore() throws -> (directory: URL, store: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KonomiPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("Konomi.store"))
    }

    private func configuration(at url: URL, allowsSave: Bool = true) -> ModelConfiguration {
        ModelConfiguration(
            schema: PersistenceBootstrap.schema,
            url: url,
            allowsSave: allowsSave
        )
    }

    @Test func newStoreKeepsOneSettingsRowAcrossBootstrap() throws {
        let location = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        try autoreleasepool {
            let container = try PersistenceBootstrap.makeContainer(
                configuration: configuration(at: location.store)
            )
            let settings = try container.mainContext.fetch(FetchDescriptor<AppSettings>())
            #expect(settings.count == 1)
        }

        try autoreleasepool {
            let container = try PersistenceBootstrap.makeContainer(
                configuration: configuration(at: location.store)
            )
            let settings = try container.mainContext.fetch(FetchDescriptor<AppSettings>())
            #expect(settings.count == 1)
        }
    }

    @Test func legacyCleanupPreservesValidDataAndIsIdempotent() throws {
        let location = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        let itemID = UUID()
        let validDetailID = UUID()
        let emptyAttachedDetailID = UUID()
        let orphanDetailID = UUID()
        let keptProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let tiedProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let oldProfileID = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        var expectedRecommendationIDs = Set<UUID>()
        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: location.store)]
            )
            let context = container.mainContext

            let settings = AppSettings()
            settings.showPublicScores = false
            settings.serendipityIntensity = 0.8
            context.insert(settings)

            let item = MediaItem()
            item.id = itemID
            item.title = "Sentinel Library Item"
            item.notes = "Must survive maintenance"
            let validDetail = DetailedRating()
            validDetail.id = validDetailID
            validDetail.moodTagsRaw = ["reflective"]
            validDetail.recommendFactor = 4
            item.detailedRating = validDetail
            context.insert(item)

            let emptyItem = MediaItem()
            emptyItem.title = "Empty Detail Owner"
            let emptyAttachedDetail = DetailedRating()
            emptyAttachedDetail.id = emptyAttachedDetailID
            emptyItem.detailedRating = emptyAttachedDetail
            context.insert(emptyItem)

            let orphanDetail = DetailedRating()
            orphanDetail.id = orphanDetailID
            orphanDetail.rewatchFactor = 3
            context.insert(orphanDetail)

            let keptProfile = TasteProfile()
            keptProfile.id = keptProfileID
            keptProfile.lastUpdated = fixedDate
            keptProfile.tasteDescription = "Newest tie winner"
            context.insert(keptProfile)

            let tiedProfile = TasteProfile()
            tiedProfile.id = tiedProfileID
            tiedProfile.lastUpdated = fixedDate
            tiedProfile.tasteDescription = "Newest tie loser"
            context.insert(tiedProfile)

            let oldProfile = TasteProfile()
            oldProfile.id = oldProfileID
            oldProfile.lastUpdated = fixedDate.addingTimeInterval(-100)
            context.insert(oldProfile)

            for index in 0..<12 {
                let recommendation = Recommendation()
                recommendation.id = UUID()
                recommendation.mediaType = .movie
                recommendation.title = "Unique \(index)"
                recommendation.creator = "Creator"
                recommendation.generatedDate = fixedDate.addingTimeInterval(Double(-index))
                recommendation.wasAdded = index == 3
                recommendation.wasDismissed = index == 4
                context.insert(recommendation)
                if index < 10 {
                    expectedRecommendationIDs.insert(recommendation.id)
                }
            }

            let duplicate = Recommendation()
            duplicate.mediaType = .movie
            duplicate.title = "  ÚNIQUE   0  "
            duplicate.creator = " creator\n"
            duplicate.generatedDate = fixedDate.addingTimeInterval(-0.5)
            context.insert(duplicate)

            try context.save()
        }

        for pass in 1...2 {
            try autoreleasepool {
                let container = try PersistenceBootstrap.makeContainer(
                    configuration: configuration(at: location.store)
                )
                let context = container.mainContext

                let items = try context.fetch(FetchDescriptor<MediaItem>())
                let sentinel = try #require(items.first { $0.id == itemID })
                #expect(sentinel.title == "Sentinel Library Item")
                #expect(sentinel.notes == "Must survive maintenance")
                #expect(sentinel.detailedRating?.id == validDetailID)
                #expect(sentinel.detailedRating?.moodTagsRaw == ["reflective"])
                #expect(sentinel.detailedRating?.recommendFactor == 4)
                #expect(items.first { $0.title == "Empty Detail Owner" }?.detailedRating == nil)

                let details = try context.fetch(FetchDescriptor<DetailedRating>())
                #expect(details.map(\.id) == [validDetailID])
                #expect(!details.contains { $0.id == emptyAttachedDetailID || $0.id == orphanDetailID })

                let settings = try context.fetch(FetchDescriptor<AppSettings>())
                #expect(settings.count == 1)
                #expect(settings[0].showPublicScores == false)
                #expect(settings[0].serendipityIntensity == 0.8)

                let profiles = try context.fetch(FetchDescriptor<TasteProfile>())
                #expect(profiles.map(\.id) == [keptProfileID])

                let recommendations = try context.fetch(FetchDescriptor<Recommendation>())
                #expect(recommendations.count == 10)
                #expect(Set(recommendations.map(\.id)) == expectedRecommendationIDs)
                #expect(recommendations.contains { $0.wasAdded })
                #expect(recommendations.contains { $0.wasDismissed })

                if pass == 1 {
                    // Releasing this scoped container before the second pass proves reopening is stable.
                    #expect(context.hasChanges == false)
                }
            }
        }
    }

    @Test func emptyDetailedRatingWriteIsANoOp() throws {
        let container = try ModelContainer(
            for: PersistenceBootstrap.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let item = MediaItem()
        context.insert(item)

        item.updateDetailedRating(in: context) { rating in
            rating.emotionalResponses = []
            rating.moodTags = []
            rating.rewatchFactor = 0
            rating.recommendFactor = 0
        }
        try context.save()

        #expect(item.detailedRating == nil)
        #expect(try context.fetch(FetchDescriptor<DetailedRating>()).isEmpty)
    }

    @Test func detailedRatingChildIsReusedThenDeletedWhenCleared() throws {
        let container = try ModelContainer(
            for: PersistenceBootstrap.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let item = MediaItem()
        context.insert(item)

        item.updateDetailedRating(in: context) { $0.rewatchFactor = 4 }
        try context.save()
        let childID = try #require(item.detailedRating?.id)
        #expect(try context.fetch(FetchDescriptor<DetailedRating>()).count == 1)

        item.updateDetailedRating(in: context) { $0.recommendFactor = 5 }
        try context.save()
        #expect(item.detailedRating?.id == childID)
        #expect(item.detailedRating?.recommendFactor == 5)
        #expect(try context.fetch(FetchDescriptor<DetailedRating>()).count == 1)

        item.updateDetailedRating(in: context) { rating in
            rating.rewatchFactor = 0
            rating.recommendFactor = 0
        }
        try context.save()
        #expect(item.detailedRating == nil)
        #expect(try context.fetch(FetchDescriptor<DetailedRating>()).isEmpty)
    }

    @Test func profileReplacementLeavesOnlyTheNewProfile() throws {
        let container = try ModelContainer(
            for: PersistenceBootstrap.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let oldOne = TasteProfile()
        let oldTwo = TasteProfile()
        context.insert(oldOne)
        context.insert(oldTwo)
        try context.save()

        let replacement = TasteProfile()
        replacement.tasteDescription = "Current profile"
        try GeneratedContentStore.replaceTasteProfile(replacement, in: context)

        let profiles = try context.fetch(FetchDescriptor<TasteProfile>())
        #expect(profiles.map(\.id) == [replacement.id])
        #expect(profiles[0].tasteDescription == "Current profile")
    }

    @Test func recommendationReplacementDeduplicatesCapsAndRemovesOldRows() throws {
        let container = try ModelContainer(
            for: PersistenceBootstrap.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let oldOne = Recommendation()
        oldOne.title = "Old One"
        let oldTwo = Recommendation()
        oldTwo.title = "Old Two"
        context.insert(oldOne)
        context.insert(oldTwo)
        try context.save()
        let oldIDs = Set([oldOne.id, oldTwo.id])

        var candidates: [Recommendation] = []
        for index in 0..<12 {
            let recommendation = Recommendation()
            recommendation.mediaType = .book
            recommendation.title = "Candidate \(index)"
            recommendation.creator = "Writer"
            candidates.append(recommendation)
        }
        let titleDuplicate = Recommendation()
        titleDuplicate.mediaType = .book
        titleDuplicate.title = "  CÁNDIDATE\n0 "
        titleDuplicate.creator = " writer "
        candidates.insert(titleDuplicate, at: 1)

        let externalOriginal = Recommendation()
        externalOriginal.mediaType = .movie
        externalOriginal.title = "External A"
        externalOriginal.tmdbID = 42
        candidates.insert(externalOriginal, at: 2)

        let externalDuplicate = Recommendation()
        externalDuplicate.mediaType = .movie
        externalDuplicate.title = "Different title"
        externalDuplicate.tmdbID = 42
        candidates.insert(externalDuplicate, at: 3)

        let expectedIDs = Array(candidates.reduce(into: [Recommendation]()) { retained, candidate in
            guard retained.count < 10,
                  !retained.contains(where: { $0.identityKey == candidate.identityKey }) else { return }
            retained.append(candidate)
        }.map(\.id))

        let retained = try GeneratedContentStore.replaceRecommendations(candidates, in: context)
        let persisted = try context.fetch(FetchDescriptor<Recommendation>())

        #expect(retained.map(\.id) == expectedIDs)
        #expect(Set(persisted.map(\.id)) == Set(expectedIDs))
        #expect(persisted.count == 10)
        #expect(Set(persisted.map(\.id)).isDisjoint(with: oldIDs))
    }

    @Test func emptyRecommendationReplacementPreservesExistingSnapshot() throws {
        let container = try ModelContainer(
            for: PersistenceBootstrap.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let existing = Recommendation()
        existing.title = "Keep Me"
        context.insert(existing)
        try context.save()

        do {
            _ = try GeneratedContentStore.replaceRecommendations([], in: context)
            Issue.record("Expected an empty recommendation error")
        } catch let error as GeneratedContentStoreError {
            #expect(error == .emptyRecommendations)
            #expect(error.localizedDescription.contains("previous recommendations were kept"))
        }

        let persisted = try context.fetch(FetchDescriptor<Recommendation>())
        #expect(persisted.map(\.id) == [existing.id])
    }

    @Test func recommendationSaveFailureRollsBackAndPreservesDiskSnapshot() throws {
        let location = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let oldID = UUID()

        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: location.store)]
            )
            let existing = Recommendation()
            existing.id = oldID
            existing.title = "Disk Snapshot"
            container.mainContext.insert(existing)
            try container.mainContext.save()
        }

        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: location.store, allowsSave: false)]
            )
            let context = container.mainContext
            let prior = try context.fetch(FetchDescriptor<Recommendation>())
            #expect(prior.map(\.id) == [oldID])

            let replacement = Recommendation()
            replacement.title = "Must Not Persist"
            #expect(throws: (any Error).self) {
                _ = try GeneratedContentStore.replaceRecommendations([replacement], in: context)
            }
            #expect(try context.fetch(FetchDescriptor<Recommendation>()).map(\.id) == [oldID])
            #expect(context.hasChanges == false)
        }

        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: location.store)]
            )
            let persisted = try container.mainContext.fetch(FetchDescriptor<Recommendation>())
            #expect(persisted.map(\.id) == [oldID])
            #expect(persisted[0].title == "Disk Snapshot")
        }
    }

    @Test func repeatedBootstrapFailureStaysRecoverableAndUpdatesDetails() async {
        enum FactoryError: LocalizedError {
            case first
            case second

            var errorDescription: String? {
                switch self {
                case .first: "First bootstrap failure"
                case .second: "Second bootstrap failure"
                }
            }
        }

        var attempts = 0
        let state = PersistenceState(factory: {
            attempts += 1
            throw attempts == 1 ? FactoryError.first : FactoryError.second
        }, simulateFailureOnce: false)

        #expect(attempts == 1)
        #expect(state.container == nil)
        #expect(state.failureDetails == "First bootstrap failure")
        #expect(state.isRetrying == false)

        await state.retry()

        #expect(attempts == 2)
        #expect(state.container == nil)
        #expect(state.failureDetails == "Second bootstrap failure")
        #expect(state.isRetrying == false)
    }
}
