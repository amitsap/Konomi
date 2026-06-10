import Foundation
import SwiftData

@Model
final class DetailedRating {
    var id: UUID = UUID()
    var emotionalResponsesRaw: [String] = []
    var moodTagsRaw: [String] = []
    var rewatchFactor: Int = 0      // 1–5
    var recommendFactor: Int = 0    // 1–5
    var dateRated: Date = Date()

    init() {}

    var emotionalResponses: [EmotionalResponse] {
        get { emotionalResponsesRaw.compactMap { EmotionalResponse(rawValue: $0) } }
        set { emotionalResponsesRaw = newValue.map(\.rawValue) }
    }

    var moodTags: [MoodTag] {
        get { moodTagsRaw.compactMap { MoodTag(rawValue: $0) } }
        set { moodTagsRaw = newValue.map(\.rawValue) }
    }
}
