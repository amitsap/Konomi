import Foundation
import SwiftData

struct DetailedRatingDeletionSnapshot: Equatable {
    let id: UUID
    let emotionalResponsesRaw: [String]
    let moodTagsRaw: [String]
    let rewatchFactor: Int
    let recommendFactor: Int
    let dateRated: Date

    init(_ rating: DetailedRating) {
        id = rating.id
        emotionalResponsesRaw = rating.emotionalResponsesRaw
        moodTagsRaw = rating.moodTagsRaw
        rewatchFactor = rating.rewatchFactor
        recommendFactor = rating.recommendFactor
        dateRated = rating.dateRated
    }

    func makeModel() -> DetailedRating {
        let rating = DetailedRating()
        rating.id = id
        rating.emotionalResponsesRaw = emotionalResponsesRaw
        rating.moodTagsRaw = moodTagsRaw
        rating.rewatchFactor = rewatchFactor
        rating.recommendFactor = recommendFactor
        rating.dateRated = dateRated
        return rating
    }
}

struct MediaItemDeletionSnapshot: Equatable {
    let id: UUID
    let mediaTypeRaw: String
    let statusRaw: String
    let title: String
    let originalTitle: String?
    let creator: String
    let year: Int?
    let coverURLString: String?
    let coverImageData: Data?
    let synopsis: String?
    let genres: [String]
    let tags: [String]
    let tmdbID: Int?
    let openLibraryID: String?
    let isbn: String?
    let publicScore: Double?
    let publicVoteCount: Int?
    let personalScore: Int?
    let dateAdded: Date
    let dateStarted: Date?
    let dateCompleted: Date?
    let dateAbandoned: Date?
    let review: String?
    let notes: String?
    let isFavorite: Bool
    let recommendedByAI: Bool
    let serendipityScore: Double?
    let publicRatingGap: Double?
    let recommendationReason: String?
    let runtime: Int?
    let pageCount: Int?
    let seasonCount: Int?
    let detailedRating: DetailedRatingDeletionSnapshot?

    init(_ item: MediaItem) {
        id = item.id
        mediaTypeRaw = item.mediaTypeRaw
        statusRaw = item.statusRaw
        title = item.title
        originalTitle = item.originalTitle
        creator = item.creator
        year = item.year
        coverURLString = item.coverURLString
        coverImageData = item.coverImageData
        synopsis = item.synopsis
        genres = item.genres
        tags = item.tags
        tmdbID = item.tmdbID
        openLibraryID = item.openLibraryID
        isbn = item.isbn
        publicScore = item.publicScore
        publicVoteCount = item.publicVoteCount
        personalScore = item.personalScore
        dateAdded = item.dateAdded
        dateStarted = item.dateStarted
        dateCompleted = item.dateCompleted
        dateAbandoned = item.dateAbandoned
        review = item.review
        notes = item.notes
        isFavorite = item.isFavorite
        recommendedByAI = item.recommendedByAI
        serendipityScore = item.serendipityScore
        publicRatingGap = item.publicRatingGap
        recommendationReason = item.recommendationReason
        runtime = item.runtime
        pageCount = item.pageCount
        seasonCount = item.seasonCount
        if let rating = item.detailedRating {
            detailedRating = DetailedRatingDeletionSnapshot(rating)
        } else {
            detailedRating = nil
        }
    }

    func makeModel() -> MediaItem {
        let item = MediaItem()
        item.id = id
        item.mediaTypeRaw = mediaTypeRaw
        item.statusRaw = statusRaw
        item.title = title
        item.originalTitle = originalTitle
        item.creator = creator
        item.year = year
        item.coverURLString = coverURLString
        item.coverImageData = coverImageData
        item.synopsis = synopsis
        item.genres = genres
        item.tags = tags
        item.tmdbID = tmdbID
        item.openLibraryID = openLibraryID
        item.isbn = isbn
        item.publicScore = publicScore
        item.publicVoteCount = publicVoteCount
        item.personalScore = personalScore
        item.dateAdded = dateAdded
        item.dateStarted = dateStarted
        item.dateCompleted = dateCompleted
        item.dateAbandoned = dateAbandoned
        item.review = review
        item.notes = notes
        item.isFavorite = isFavorite
        item.recommendedByAI = recommendedByAI
        item.serendipityScore = serendipityScore
        item.publicRatingGap = publicRatingGap
        item.recommendationReason = recommendationReason
        item.runtime = runtime
        item.pageCount = pageCount
        item.seasonCount = seasonCount
        item.detailedRating = detailedRating?.makeModel()
        return item
    }
}

enum MediaItemDeletionRestoreResult: Equatable {
    case restored
    case alreadyPresent
}

enum MediaItemDeletionStore {
    static func delete(
        _ item: MediaItem,
        in context: ModelContext
    ) throws -> MediaItemDeletionSnapshot {
        if context.hasChanges {
            try context.save()
        }

        let snapshot = MediaItemDeletionSnapshot(item)
        let persistentModelID = item.persistentModelID
        let deletionContext = ModelContext(context.container)
        guard let persistedItem = deletionContext.model(for: persistentModelID) as? MediaItem else {
            throw MediaItemDeletionStoreError.missingItem
        }

        deletionContext.delete(persistedItem)
        do {
            try deletionContext.save()
            return snapshot
        } catch {
            deletionContext.rollback()
            throw error
        }
    }

    static func restore(
        _ snapshot: MediaItemDeletionSnapshot,
        in context: ModelContext
    ) throws -> MediaItemDeletionRestoreResult {
        if context.hasChanges {
            try context.save()
        }

        let itemID = snapshot.id
        let restorationContext = ModelContext(context.container)
        let existing = try restorationContext.fetch(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == itemID })
        )
        guard existing.isEmpty else { return .alreadyPresent }

        restorationContext.insert(snapshot.makeModel())
        do {
            try restorationContext.save()
            return .restored
        } catch {
            restorationContext.rollback()
            throw error
        }
    }
}

enum MediaItemDeletionStoreError: Error {
    case missingItem
}
