import Foundation
import SwiftData

// MARK: - Claude response types

private struct TasteProfileResponse: Decodable {
    let tasteDescription: String
    let favoriteGenres: [String]
    let favoriteCreators: [String]
    let favoriteThemes: [String]
    let avoidPatterns: [String]
    let strongPatterns: [String]
}

private struct RecommendationsResponse: Decodable {
    let recommendations: [RecommendationItem]

    private enum CodingKeys: String, CodingKey {
        case recommendations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var rows = try container.nestedUnkeyedContainer(forKey: .recommendations)
        var decoded: [RecommendationItem] = []

        while !rows.isAtEnd {
            let rowDecoder = try rows.superDecoder()
            if let item = try? RecommendationItem(from: rowDecoder) {
                decoded.append(item)
            }
        }
        recommendations = decoded
    }

    struct RecommendationItem: Decodable {
        let title: String
        let creator: String
        let year: Int?
        let mediaType: String
        let genres: [String]
        let synopsis: String
        let predictedPersonalScore: Double
        let publicScore: Double?
        let serendipityScore: Double
        let isSerendipitous: Bool
        let recommendationReason: String
        let serendipityExplanation: String?
    }
}

// MARK: - Service

@Observable
final class TasteAnalysisService {
    var isGenerating: Bool = false
    var lastError: String?

    static let minimumRatedItems = 5

    static func ratedCompleted(_ items: [MediaItem]) -> [MediaItem] {
        items.filter { $0.isCompleted && $0.personalScore != nil }
    }

    static func averagePersonalScore(_ items: [MediaItem]) -> Double {
        let rated = ratedCompleted(items)
        guard !rated.isEmpty else { return 0 }
        return rated.reduce(0.0) { $0 + Double($1.personalScore ?? 0) } / Double(rated.count)
    }

    // MARK: - Taste Profile

    func generateTasteProfile(items: [MediaItem]) async throws -> TasteProfile {
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        let prompt = buildTasteProfilePrompt(items: items)
        let responseText = try await ClaudeService.sendWithSystem(
            tasteProfileSystemPrompt,
            user: prompt,
            options: .tasteProfile
        )
        let response = try ClaudeService.decode(TasteProfileResponse.self, from: responseText)

        let profile = TasteProfile()
        profile.tasteDescription = response.tasteDescription
        profile.favoriteGenres = response.favoriteGenres
        profile.favoriteCreators = response.favoriteCreators
        profile.favoriteThemes = response.favoriteThemes
        profile.avoidPatterns = response.avoidPatterns
        profile.strongPatterns = response.strongPatterns
        profile.averagePersonalScore = Self.averagePersonalScore(items)
        profile.totalCompleted = items.filter(\.isCompleted).count
        profile.lastUpdated = Date()
        return profile
    }

    // MARK: - Recommendations

    func generateRecommendations(
        profile: TasteProfile,
        existingLibrary: [MediaItem],
        mediaType: MediaType? = nil,
        excludedRecommendations: [Recommendation] = [],
        serendipityLevel: SerendipityLevel = .balanced,
        surpriseMode: Bool = false
    ) async throws -> [Recommendation] {
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        let request = recommendationRequest(
            profile: profile,
            existingLibrary: existingLibrary,
            excludedRecommendations: excludedRecommendations,
            mediaType: mediaType,
            serendipityLevel: serendipityLevel,
            surpriseMode: surpriseMode
        )
        let responseText = try await ClaudeService.sendWithSystem(
            request.system,
            user: request.user,
            options: .recommendations
        )
        return try recommendations(
            from: responseText,
            mediaType: mediaType,
            surpriseMode: surpriseMode
        )
    }

    func recommendations(
        from responseText: String,
        mediaType requestedMediaType: MediaType?,
        surpriseMode: Bool
    ) throws -> [Recommendation] {
        let response = try ClaudeService.decode(RecommendationsResponse.self, from: responseText)

        return response.recommendations.compactMap { item in
            guard let mediaType = MediaType(rawValue: item.mediaType),
                  requestedMediaType == nil || requestedMediaType == mediaType else {
                return nil
            }
            let rec = Recommendation()
            rec.title = item.title
            rec.creator = item.creator
            rec.year = item.year
            rec.mediaType = mediaType
            rec.genres = item.genres
            rec.synopsis = item.synopsis
            rec.predictedPersonalScore = item.predictedPersonalScore
            rec.publicScore = item.publicScore
            rec.serendipityScore = item.serendipityScore
            rec.isSerendipitous = item.isSerendipitous || surpriseMode
            rec.recommendationReason = item.recommendationReason
            rec.serendipityExplanation = item.serendipityExplanation
            rec.generatedDate = Date()
            return rec
        }
    }

    // MARK: - Serendipity Explanation

    func generateSerendipityExplanation(for rec: Recommendation, profile: TasteProfile) async throws -> String {
        let prompt = """
        This person's taste profile: \(profile.tasteDescription)

        They rated items highly that have these patterns: \(profile.strongPatterns.joined(separator: ", "))

        You recommended: "\(rec.title)" (\(rec.year ?? 0)) by \(rec.creator)
        Public score: \(rec.publicScoreDisplay)/10
        Your predicted personal score for them: \(rec.predictedScoreDisplay)/10

        In 1-2 sentences, explain specifically why the public score underestimates this work for this person's specific taste.
        Be concrete — reference their actual taste patterns.
        """
        return try await ClaudeService.sendWithSystem(
            "You are a perceptive media critic who explains why overlooked works suit specific tastes.",
            user: prompt,
            options: .serendipityExplanation
        )
    }

    // MARK: - Prompt builders

    func buildTasteProfilePrompt(items: [MediaItem]) -> String {
        let completed = Self.ratedCompleted(items).sorted { ($0.personalScore ?? 0) > ($1.personalScore ?? 0) }
        let abandoned = items.filter { $0.status == .abandoned }

        var lines: [String] = []

        let loved = completed.filter { ($0.personalScore ?? 0) >= 8 }
        if !loved.isEmpty {
            lines.append("LOVED (8–10):")
            for item in loved {
                var line = "- \(item.title) (\(item.year ?? 0)) by \(item.creator) — My rating: \(item.personalScore ?? 0)/10"
                if !item.genres.isEmpty { line += ", genres: \(item.genres.joined(separator: ", "))" }
                if let dr = item.detailedRating, !dr.emotionalResponsesRaw.isEmpty {
                    line += ", emotions: \(dr.emotionalResponses.map(\.displayName).joined(separator: ", "))"
                }
                if let review = item.review, !review.isEmpty {
                    line += "\n  My notes: \(review.prefix(200))"
                }
                lines.append(line)
            }
        }

        let liked = completed.filter { let s = $0.personalScore ?? 0; return s >= 5 && s < 8 }
        if !liked.isEmpty {
            lines.append("\nLIKED (5–7):")
            for item in liked {
                var line = "- \(item.title) (\(item.year ?? 0)) by \(item.creator) — My rating: \(item.personalScore ?? 0)/10"
                if !item.genres.isEmpty { line += ", genres: \(item.genres.joined(separator: ", "))" }
                lines.append(line)
            }
        }

        let disliked = completed.filter { ($0.personalScore ?? 0) < 5 }
        if !disliked.isEmpty {
            lines.append("\nDISLIKED (1–4):")
            for item in disliked {
                lines.append("- \(item.title) by \(item.creator) — My rating: \(item.personalScore ?? 0)/10")
            }
        }

        if !abandoned.isEmpty {
            lines.append("\nABANDONED (did not finish):")
            for item in abandoned {
                lines.append("- \(item.title) by \(item.creator)")
            }
        }

        return lines.joined(separator: "\n") + "\n\nAnalyse my taste and return the JSON profile."
    }

    func buildRecommendationsPrompt(
        profile: TasteProfile,
        existingLibrary: [MediaItem],
        excludedRecommendations: [Recommendation] = [],
        mediaType: MediaType? = nil,
        serendipityLevel: SerendipityLevel
    ) -> String {
        sharedRecommendationsPrompt(
            profile: profile,
            existingLibrary: existingLibrary,
            excludedRecommendations: excludedRecommendations,
            mediaType: mediaType
        ) + "\n\(serendipityLevel.promptGuidance)\nReturn the JSON array as specified."
    }

    func recommendationRequest(
        profile: TasteProfile,
        existingLibrary: [MediaItem],
        excludedRecommendations: [Recommendation] = [],
        mediaType: MediaType? = nil,
        serendipityLevel: SerendipityLevel,
        surpriseMode: Bool
    ) -> (system: String, user: String) {
        let system = surpriseMode
            ? recommendationsSystemPrompt + "\n\n" + surpriseModeAddendum
            : recommendationsSystemPrompt
        let sharedPrompt = sharedRecommendationsPrompt(
            profile: profile,
            existingLibrary: existingLibrary,
            excludedRecommendations: excludedRecommendations,
            mediaType: mediaType
        )
        let user = surpriseMode
            ? sharedPrompt + "\nReturn the JSON array as specified."
            : buildRecommendationsPrompt(
                profile: profile,
                existingLibrary: existingLibrary,
                excludedRecommendations: excludedRecommendations,
                mediaType: mediaType,
                serendipityLevel: serendipityLevel
            )
        return (system, user)
    }

    private func sharedRecommendationsPrompt(
        profile: TasteProfile,
        existingLibrary: [MediaItem],
        excludedRecommendations: [Recommendation],
        mediaType: MediaType?
    ) -> String {
        let librarySummary = summarizedLibraryForRecommendations(existingLibrary)
        let recommendationSummary = summarizedRecommendations(excludedRecommendations)
        let scope: String
        if let mediaType {
            scope = "Generate exactly 10 recommendations with mediaType \"\(mediaType.rawValue)\" and no other media type."
        } else {
            scope = "Generate exactly 10 recommendations containing all three mediaType values: at least one \"book\", one \"movie\", and one \"tvShow\"."
        }

        return """
        My taste profile:
        \(profile.tasteDescription)

        My favourite themes and patterns: \(profile.strongPatterns.joined(separator: "; "))
        My favourite genres: \(profile.favoriteGenres.joined(separator: ", "))
        My favourite creators: \(profile.favoriteCreators.joined(separator: ", "))
        Things I tend to dislike: \(profile.avoidPatterns.joined(separator: ", "))
        My average personal score: \(String(format: "%.1f", profile.averagePersonalScore))/10

        Items already in my library (do NOT recommend these exact titles):
        \(librarySummary)

        Items just recommended in the current set (do NOT repeat these exact titles):
        \(recommendationSummary)

        \(scope)
        """
    }

    private func summarizedRecommendations(_ recommendations: [Recommendation]) -> String {
        guard !recommendations.isEmpty else { return "None yet" }
        return recommendations.map { recommendation in
            let creator = recommendation.creator.trimmingCharacters(in: .whitespacesAndNewlines)
            return creator.isEmpty ? recommendation.title : "\(recommendation.title) by \(creator)"
        }.joined(separator: ", ")
    }

    private func summarizedLibraryForRecommendations(_ existingLibrary: [MediaItem]) -> String {
        guard !existingLibrary.isEmpty else { return "None yet" }

        let prioritized = existingLibrary.sorted { lhs, rhs in
            let lhsScore = lhs.personalScore ?? (lhs.isCompleted ? 1 : 0)
            let rhsScore = rhs.personalScore ?? (rhs.isCompleted ? 1 : 0)

            if lhsScore == rhsScore {
                return lhs.dateAdded > rhs.dateAdded
            }
            return lhsScore > rhsScore
        }

        let limit = 220
        let sampled = prioritized.prefix(limit).map { item in
            let creator = item.creator.trimmingCharacters(in: .whitespacesAndNewlines)
            if creator.isEmpty {
                return item.title
            }
            return "\(item.title) by \(creator)"
        }

        let omittedCount = max(0, existingLibrary.count - sampled.count)
        if omittedCount > 0 {
            return sampled.joined(separator: ", ") + ", plus \(omittedCount) more already-owned titles."
        }

        return sampled.joined(separator: ", ")
    }

    // MARK: - System prompts

    private let tasteProfileSystemPrompt = """
    You are a sophisticated media critic and taste analyst. Analyse a person's consumption history and ratings to identify deep patterns in their taste — not just genre preferences but narrative styles, thematic interests, tonal preferences, and the qualities that make them love or hate specific works.

    Be specific and insightful. Go beyond "likes thrillers" to "drawn to psychological complexity and moral ambiguity."

    Return JSON in exactly this format:
    ```json
    {
      "tasteDescription": "2-3 paragraph editorial description of their taste in the second person (you are drawn to...)",
      "favoriteGenres": ["string"],
      "favoriteCreators": ["string"],
      "favoriteThemes": ["string"],
      "avoidPatterns": ["string"],
      "strongPatterns": ["e.g. unreliable narrators, slow-burn pacing, psychological depth"]
    }
    ```
    Return only the JSON block. No other text.
    """

    private let recommendationsSystemPrompt = """
    You are a personal media curator who knows this person's taste deeply. Recommend books, movies, and TV shows they would personally love.

    IMPORTANT: Do not filter by public ratings. A work rated 6.5 publicly may be perfect for this person. Focus entirely on predicted personal match.

    For each recommendation:
    - Predict their personal score (1–10) based on their taste patterns
    - Set serendipityScore (0.0–1.0): higher means more surprising/unconventional for them
    - Flag isSerendipitous = true if public rating is below 7.5 AND predicted personal score is above 7.5
    - Keep synopsis to 1 compact sentence
    - Keep recommendationReason to 1-2 compact sentences that reference their specific taste patterns
    - If serendipitous, keep serendipityExplanation to 1 compact sentence about why the crowd underrates this for them

    Return JSON in exactly this format:
    ```json
    {
      "recommendations": [
        {
          "title": "string",
          "creator": "string",
          "year": 2019,
          "mediaType": "book|movie|tvShow",
          "genres": ["string"],
          "synopsis": "1 short sentence",
          "predictedPersonalScore": 8.5,
          "publicScore": 6.4,
          "serendipityScore": 0.75,
          "isSerendipitous": true,
          "recommendationReason": "string",
          "serendipityExplanation": "string or null"
        }
      ]
    }
    ```
    Return exactly 10 recommendations.
    Return only the JSON block. No other text.
    """

    private let surpriseModeAddendum = """
    SURPRISE ME MODE ACTIVE:
    Only recommend works with public ratings below 7.5. These should be hidden gems, cult classics, overlooked masterpieces, or critically misunderstood works.

    For each pick explain specifically why the crowd got it wrong for this person — why their personal taste makes this a better fit than the public score suggests.

    All 10 recommendations must be serendipitous (isSerendipitous = true for all).
    Set serendipityScore above 0.6 for all picks.
    """
}
