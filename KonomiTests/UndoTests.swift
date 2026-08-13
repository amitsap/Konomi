import Foundation
import SwiftData
import Testing
@testable import Konomi

@MainActor
struct UndoTests {
    private func temporaryStore() throws -> (directory: URL, store: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KonomiUndoTests-\(UUID().uuidString)", isDirectory: true)
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

    private func populatedItem() -> MediaItem {
        let detail = DetailedRating()
        detail.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        detail.emotionalResponsesRaw = ["moved", "inspired"]
        detail.moodTagsRaw = ["reflective", "intense"]
        detail.rewatchFactor = 4
        detail.recommendFactor = 5
        detail.dateRated = Date(timeIntervalSince1970: 1_700_345_600)

        let item = MediaItem()
        item.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        item.mediaTypeRaw = "future-media-type"
        item.statusRaw = "future-status"
        item.title = "Dune 🏜️"
        item.originalTitle = "Dune: The Desert Planet"
        item.creator = "Frank Herbert"
        item.year = 1965
        item.coverURLString = "https://example.com/dune.jpg"
        item.coverImageData = Data([0x01, 0x02, 0x03])
        item.synopsis = "A struggle over spice and power."
        item.genres = ["Science Fiction", "Adventure"]
        item.tags = ["favourite", "reread"]
        item.tmdbID = 123
        item.openLibraryID = "OL893415W"
        item.isbn = "9780441172719"
        item.publicScore = 8.7
        item.publicVoteCount = 42_000
        item.personalScore = 9
        item.dateAdded = Date(timeIntervalSince1970: 1_700_000_000)
        item.dateStarted = Date(timeIntervalSince1970: 1_700_086_400)
        item.dateCompleted = Date(timeIntervalSince1970: 1_700_172_800)
        item.dateAbandoned = Date(timeIntervalSince1970: 1_700_259_200)
        item.review = "Monumental world-building."
        item.notes = "Revisit the ecology chapters."
        item.isFavorite = true
        item.recommendedByAI = true
        item.serendipityScore = 0.72
        item.publicRatingGap = 0.3
        item.recommendationReason = "Political science fiction is a strong match."
        item.runtime = 155
        item.pageCount = 688
        item.seasonCount = 2
        item.detailedRating = detail
        return item
    }

    private func expectExactMatch(
        _ item: MediaItem,
        snapshot: MediaItemDeletionSnapshot
    ) throws {
        #expect(item.id == snapshot.id)
        #expect(item.mediaTypeRaw == snapshot.mediaTypeRaw)
        #expect(item.statusRaw == snapshot.statusRaw)
        #expect(item.title == snapshot.title)
        #expect(item.originalTitle == snapshot.originalTitle)
        #expect(item.creator == snapshot.creator)
        #expect(item.year == snapshot.year)
        #expect(item.coverURLString == snapshot.coverURLString)
        #expect(item.coverImageData == snapshot.coverImageData)
        #expect(item.synopsis == snapshot.synopsis)
        #expect(item.genres == snapshot.genres)
        #expect(item.tags == snapshot.tags)
        #expect(item.tmdbID == snapshot.tmdbID)
        #expect(item.openLibraryID == snapshot.openLibraryID)
        #expect(item.isbn == snapshot.isbn)
        #expect(item.publicScore == snapshot.publicScore)
        #expect(item.publicVoteCount == snapshot.publicVoteCount)
        #expect(item.personalScore == snapshot.personalScore)
        #expect(item.dateAdded == snapshot.dateAdded)
        #expect(item.dateStarted == snapshot.dateStarted)
        #expect(item.dateCompleted == snapshot.dateCompleted)
        #expect(item.dateAbandoned == snapshot.dateAbandoned)
        #expect(item.review == snapshot.review)
        #expect(item.notes == snapshot.notes)
        #expect(item.isFavorite == snapshot.isFavorite)
        #expect(item.recommendedByAI == snapshot.recommendedByAI)
        #expect(item.serendipityScore == snapshot.serendipityScore)
        #expect(item.publicRatingGap == snapshot.publicRatingGap)
        #expect(item.recommendationReason == snapshot.recommendationReason)
        #expect(item.runtime == snapshot.runtime)
        #expect(item.pageCount == snapshot.pageCount)
        #expect(item.seasonCount == snapshot.seasonCount)

        let rating = try #require(item.detailedRating)
        let ratingSnapshot = try #require(snapshot.detailedRating)
        #expect(rating.id == ratingSnapshot.id)
        #expect(rating.emotionalResponsesRaw == ratingSnapshot.emotionalResponsesRaw)
        #expect(rating.moodTagsRaw == ratingSnapshot.moodTagsRaw)
        #expect(rating.rewatchFactor == ratingSnapshot.rewatchFactor)
        #expect(rating.recommendFactor == ratingSnapshot.recommendFactor)
        #expect(rating.dateRated == ratingSnapshot.dateRated)
    }

    @Test func savedDeletionRestorationReproducesExactGraph() throws {
        let container = try ModelContainer(
            for: PersistenceBootstrap.schema,
            configurations: ModelConfiguration(
                schema: PersistenceBootstrap.schema,
                isStoredInMemoryOnly: true
            )
        )
        let context = container.mainContext
        let item = populatedItem()
        let itemID = item.id
        let detailID = try #require(item.detailedRating?.id)
        context.insert(item)
        try context.save()

        let snapshot = try MediaItemDeletionStore.delete(item, in: context)
        let afterDeletion = ModelContext(container)
        #expect(try afterDeletion.fetch(FetchDescriptor<MediaItem>()).allSatisfy { $0.id != itemID })
        #expect(try afterDeletion.fetch(FetchDescriptor<DetailedRating>()).allSatisfy { $0.id != detailID })

        #expect(try MediaItemDeletionStore.restore(snapshot, in: context) == .restored)

        let verificationContext = ModelContext(container)
        let restored = try #require(verificationContext.fetch(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == itemID })
        ).first)
        try expectExactMatch(restored, snapshot: snapshot)
    }

    @Test func restoreDoesNotDuplicateExistingApplicationID() throws {
        let container = try ModelContainer(
            for: PersistenceBootstrap.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let item = populatedItem()
        let itemID = item.id
        let sentinel = MediaItem()
        sentinel.id = itemID
        sentinel.title = "Already restored elsewhere"
        context.insert(item)
        context.insert(sentinel)
        try context.save()
        let snapshot = try MediaItemDeletionStore.delete(item, in: context)

        let afterDeletion = try context.fetch(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == itemID })
        )
        #expect(afterDeletion.count == 1)
        #expect(afterDeletion.first?.title == "Already restored elsewhere")

        #expect(try MediaItemDeletionStore.restore(snapshot, in: context) == .alreadyPresent)
        let matches = try context.fetch(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == itemID })
        )
        #expect(matches.count == 1)
        #expect(matches.first?.title == "Already restored elsewhere")
    }

    @Test func recommendationDismissRestorePersistsAndMissingIsSafe() throws {
        let container = try ModelContainer(
            for: PersistenceBootstrap.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let recommendation = Recommendation()
        recommendation.title = "The Left Hand of Darkness"
        let recommendationID = recommendation.id
        context.insert(recommendation)
        try context.save()

        try RecommendationDismissalStore.dismiss(recommendation, in: context)
        let afterDismiss = ModelContext(container)
        #expect(try afterDismiss.fetch(
            FetchDescriptor<Recommendation>(predicate: #Predicate { $0.id == recommendationID })
        ).first?.wasDismissed == true)

        #expect(try RecommendationDismissalStore.restore(id: recommendationID, in: context) == .restored)
        let afterRestore = ModelContext(container)
        #expect(try afterRestore.fetch(
            FetchDescriptor<Recommendation>(predicate: #Predicate { $0.id == recommendationID })
        ).first?.wasDismissed == false)

        let persisted = try #require(context.fetch(
            FetchDescriptor<Recommendation>(predicate: #Predicate { $0.id == recommendationID })
        ).first)
        context.delete(persisted)
        try context.save()
        #expect(try RecommendationDismissalStore.restore(id: recommendationID, in: context) == .missing)
        #expect(try context.fetch(FetchDescriptor<Recommendation>()).isEmpty)
    }

    @Test func mutationSaveFailuresPreservePriorDiskState() throws {
        let deleteLocation = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: deleteLocation.directory) }

        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: deleteLocation.store)]
            )
            container.mainContext.insert(populatedItem())
            try container.mainContext.save()
        }

        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: deleteLocation.store, allowsSave: false)]
            )
            let context = container.mainContext
            let item = try #require(context.fetch(FetchDescriptor<MediaItem>()).first)
            #expect(throws: (any Error).self) {
                _ = try MediaItemDeletionStore.delete(item, in: context)
            }
            #expect(try context.fetch(FetchDescriptor<MediaItem>()).count == 1)
            #expect(try context.fetch(FetchDescriptor<DetailedRating>()).count == 1)
            #expect(context.hasChanges == false)
        }

        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: deleteLocation.store)]
            )
            #expect(try container.mainContext.fetch(FetchDescriptor<MediaItem>()).count == 1)
            #expect(try container.mainContext.fetch(FetchDescriptor<DetailedRating>()).count == 1)
        }

        let restoreLocation = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: restoreLocation.directory) }
        var snapshot: MediaItemDeletionSnapshot?

        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: restoreLocation.store)]
            )
            let item = populatedItem()
            container.mainContext.insert(item)
            try container.mainContext.save()
            snapshot = try MediaItemDeletionStore.delete(item, in: container.mainContext)
        }

        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: restoreLocation.store, allowsSave: false)]
            )
            let context = container.mainContext
            let capturedSnapshot = try #require(snapshot)
            #expect(throws: (any Error).self) {
                _ = try MediaItemDeletionStore.restore(capturedSnapshot, in: context)
            }
            #expect(try context.fetch(FetchDescriptor<MediaItem>()).isEmpty)
            #expect(try context.fetch(FetchDescriptor<DetailedRating>()).isEmpty)
            #expect(context.hasChanges == false)
        }

        try autoreleasepool {
            let container = try ModelContainer(
                for: PersistenceBootstrap.schema,
                configurations: [configuration(at: restoreLocation.store)]
            )
            #expect(try container.mainContext.fetch(FetchDescriptor<MediaItem>()).isEmpty)
            #expect(try container.mainContext.fetch(FetchDescriptor<DetailedRating>()).isEmpty)
        }
    }
}
