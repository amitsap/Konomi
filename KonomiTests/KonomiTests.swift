import Foundation
import SwiftData
import Testing
@testable import Konomi

struct KonomiTests {
    private struct ClaudeFixture: Decodable, Equatable {
        let name: String
        let count: Int
    }

    @MainActor
    @Test func markCompletedSetsStatusAndMissingDate() {
        let item = MediaItem()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        item.status = .inProgress
        item.dateCompleted = nil

        item.markCompleted(at: fixedDate)

        #expect(item.status == .completed)
        #expect(item.dateCompleted == fixedDate)
    }

    @MainActor
    @Test func markCompletedPreservesExistingDate() {
        let item = MediaItem()
        let existingDate = Date(timeIntervalSince1970: 1_600_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_000_000)
        item.status = .inProgress
        item.dateCompleted = existingDate

        item.markCompleted(at: newerDate)

        #expect(item.status == .completed)
        #expect(item.dateCompleted == existingDate)
    }

    @Test func requiredKeyAvailabilityTrimsWhitespace() {
        let cases: [(value: String?, expected: Bool)] = [
            (nil, false),
            ("", false),
            ("   ", false),
            ("\t\n", false),
            ("real-key", true),
            ("  real-key\n", true),
        ]

        for testCase in cases {
            #expect(KeychainService.isUsableRequiredKey(testCase.value) == testCase.expected)
        }
    }

    @Test func goodreadsCSVParserHandlesQuotedFields() throws {
        let csv = """
        Book Id,Title,Author,ISBN,ISBN13,My Rating,Average Rating,Year Published,Date Read,Date Added,Bookshelves,Exclusive Shelf,My Review,Private Notes
        1,"The Left Hand of Darkness","Ursula K. Le Guin",,9780441478125,5,4.1,1969,2024/02/03,2024/01/15,"favorites, sci-fi",read,"Loved the politics, and the ice.","Re-read soon"
        """

        let books = try GoodreadsImportService.parseCSV(data: Data(csv.utf8))

        #expect(books.count == 1)
        #expect(books[0].title == "The Left Hand of Darkness")
        #expect(books[0].author == "Ursula K. Le Guin")
        #expect(books[0].isbn13 == "9780441478125")
        #expect(books[0].myRating == 5)
        #expect(books[0].bookshelves == ["favorites", "sci-fi"])
        #expect(books[0].myReview == "Loved the politics, and the ice.")
        #expect(books[0].privateNotes == "Re-read soon")
    }

    @Test func goodreadsCSVParserRejectsWrongHeaders() throws {
        let csv = """
        Title,Author
        Test Book,Test Author
        """

        #expect(throws: GoodreadsImportError.self) {
            try GoodreadsImportService.parseCSV(data: Data(csv.utf8))
        }
    }

    // MARK: - Service URL construction

    @MainActor
    @Test func tmdbURLsPreserveSemanticQueryItems() throws {
        let query = "Fast & Furious = Tokyo"
        let key = "synthetic&key=value"
        let expectedPaths = ["/search/movie", "/search/tv"]

        for path in expectedPaths {
            let url = try TMDBService.makeURL(path: path, queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "api_key", value: key),
                URLQueryItem(name: "language", value: "en-US"),
                URLQueryItem(name: "page", value: "1"),
            ])
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let items = try #require(components.queryItems)

            #expect(components.path == "/3\(path)")
            #expect(items.count == 4)
            #expect(items.filter { $0.name == "query" }.map(\.value) == [query])
            #expect(items.filter { $0.name == "api_key" }.map(\.value) == [key])
            #expect(items.filter { $0.name == "language" }.map(\.value) == ["en-US"])
            #expect(items.filter { $0.name == "page" }.map(\.value) == ["1"])
        }
    }

    @MainActor
    @Test func openLibraryURLPreservesSemanticQueryItems() throws {
        let query = "Fire & Blood = Volume 1"
        let expectedFields = "key,title,author_name,first_publish_year,cover_i,number_of_pages_median,subject"
        let url = try OpenLibraryService.makeSearchURL(query: query)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)

        #expect(components.path == "/search.json")
        #expect(items.count == 3)
        #expect(items.filter { $0.name == "q" }.map(\.value) == [query])
        #expect(items.filter { $0.name == "fields" }.map(\.value) == [expectedFields])
        #expect(items.filter { $0.name == "limit" }.map(\.value) == ["20"])
    }

    // MARK: - Claude JSON parsing

    @Test func claudeRequestPresetsAndBodiesStayPinned() throws {
        let presets: [(ClaudeRequestOptions, String, Int)] = [
            (.tasteProfile, "high", 6_000),
            (.recommendations, "high", 16_000),
            (.serendipityExplanation, "low", 512),
            (.connectionValidation, "low", 128),
        ]

        for (options, effort, maxTokens) in presets {
            #expect(options.effort == effort)
            #expect(options.maxTokens == maxTokens)
        }

        let messages: [[String: Any]] = [["role": "user", "content": "Hello"]]
        let withoutSystem = ClaudeService.requestBody(
            messages: messages,
            system: nil,
            options: .connectionValidation
        )
        #expect(withoutSystem["model"] as? String == "claude-opus-5")
        #expect(withoutSystem["max_tokens"] as? Int == 128)
        #expect((withoutSystem["output_config"] as? [String: String])?["effort"] == "low")
        #expect(withoutSystem["system"] == nil)
        let encodedMessages = try JSONSerialization.data(withJSONObject: withoutSystem["messages"] as Any)
        let expectedMessages = try JSONSerialization.data(withJSONObject: messages)
        #expect(encodedMessages == expectedMessages)

        let withSystem = ClaudeService.requestBody(
            messages: messages,
            system: "System contract",
            options: .tasteProfile
        )
        #expect(withSystem["system"] as? String == "System contract")
        #expect(withSystem["max_tokens"] as? Int == 6_000)
        #expect((withSystem["output_config"] as? [String: String])?["effort"] == "high")
    }

    @MainActor
    @Test func claudeJSONExtractionRecognizesSupportedWrappers() {
        let cases: [(input: String, expected: String)] = [
            ("```json\n{\"name\":\"lowercase\"}\n```", "{\"name\":\"lowercase\"}"),
            ("```JSON\n{\"name\":\"uppercase\"}\n```", "{\"name\":\"uppercase\"}"),
            ("```\n{\"name\":\"generic\"}\n```", "{\"name\":\"generic\"}"),
            ("{\"name\":\"raw object\"}", "{\"name\":\"raw object\"}"),
            ("[1,2,3]", "[1,2,3]"),
            ("Here is the result: {\"name\":\"preamble\"} Hope this helps.", "{\"name\":\"preamble\"}"),
        ]

        for testCase in cases {
            #expect(ClaudeService.extractJSONPayload(from: testCase.input) == testCase.expected)
        }
    }

    @MainActor
    @Test func claudeBalancedPrefixTracksNestingStringsAndEscapes() {
        let cases: [(input: String, expected: String)] = [
            (#"{"items":[{"value":1},{"value":2}]}] trailing"#, #"{"items":[{"value":1},{"value":2}]}"#),
            (##"{"text":"He said \"hello\"","values":[1,2]}] trailing"##, ##"{"text":"He said \"hello\"","values":[1,2]}"##),
        ]

        for testCase in cases {
            #expect(ClaudeService.balancedJSONPrefix(from: testCase.input) == testCase.expected)
        }
    }

    @MainActor
    @Test func claudeDecodeSupportsCurrentRecoveryPaths() throws {
        let expected = ClaudeFixture(name: "Konomi", count: 2)
        let cases = [
            "{\"name\":\"Konomi\",\"count\":2}",
            "```json\n{\"name\":\"Konomi\",\"count\":2}\n```",
            "Result: {\"name\":\"Konomi\",\"count\":2} Done.",
            "{“name”:“Konomi”,“count”:2}",
            "{\"name\":\"Konomi\",\"count\":2}] trailing",
        ]

        for input in cases {
            let decoded = try ClaudeService.decode(ClaudeFixture.self, from: input)
            #expect(decoded == expected)
        }
    }

    @MainActor
    @Test func claudeDecodeRejectsTruncatedArraysAndGarbage() {
        let cases = [
            "[{\"name\":\"Konomi\",\"count\":2}",
            "This response contains no JSON.",
        ]

        for input in cases {
            do {
                let _ = try ClaudeService.decode(ClaudeFixture.self, from: input)
                Issue.record("Expected ClaudeError.parseError for: \(input)")
            } catch ClaudeError.parseError {
                // Expected: truncated and non-JSON responses are not recoverable.
            } catch {
                Issue.record("Expected ClaudeError.parseError, received: \(error)")
            }
        }
    }

    // MARK: - Taste profile prompt integrity

    @MainActor
    private func makeItem(title: String, creator: String, status: MediaStatus, personalScore: Int?) -> MediaItem {
        let item = MediaItem()
        item.title = title
        item.creator = creator
        item.status = status
        item.personalScore = personalScore
        return item
    }

    @MainActor
    @Test func unratedCompletedItemsAreOmittedFromPrompt() throws {
        let container = try ModelContainer(for: MediaItem.self, DetailedRating.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let unrated = makeItem(title: "Unrated Import", creator: "Some Author", status: .completed, personalScore: nil)
        let rated = makeItem(title: "Rated Book", creator: "Another Author", status: .completed, personalScore: 8)
        for item in [unrated, rated] { context.insert(item) }

        let service = TasteAnalysisService()
        let prompt = service.buildTasteProfilePrompt(items: [unrated, rated])

        #expect(!prompt.contains("Unrated Import"))
        #expect(!prompt.contains("0/10"))
        #expect(prompt.contains("Rated Book"))
    }

    @MainActor
    @Test func ratedItemsLandInCorrectBands() throws {
        let container = try ModelContainer(for: MediaItem.self, DetailedRating.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let loved = makeItem(title: "Loved Title", creator: "Creator A", status: .completed, personalScore: 9)
        let disliked = makeItem(title: "Disliked Title", creator: "Creator B", status: .completed, personalScore: 3)
        for item in [loved, disliked] { context.insert(item) }

        let service = TasteAnalysisService()
        let prompt = service.buildTasteProfilePrompt(items: [loved, disliked])

        let afterLoved = prompt.components(separatedBy: "LOVED (8–10):").last ?? ""
        let lovedSection = afterLoved.components(separatedBy: "DISLIKED (1–4):").first ?? ""
        let dislikedSection = prompt.components(separatedBy: "DISLIKED (1–4):").last ?? ""

        #expect(lovedSection.contains("Loved Title"))
        #expect(!lovedSection.contains("Disliked Title"))
        #expect(dislikedSection.contains("Disliked Title"))
        #expect(!dislikedSection.contains("Loved Title"))
    }

    @MainActor
    @Test func averagePersonalScoreIsComputedFromRatedCompletedItemsOnly() throws {
        let container = try ModelContainer(for: MediaItem.self, DetailedRating.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let ratedHigh = makeItem(title: "Eight", creator: "Creator A", status: .completed, personalScore: 8)
        let ratedLow = makeItem(title: "Four", creator: "Creator B", status: .completed, personalScore: 4)
        let unrated = makeItem(title: "Unrated", creator: "Creator C", status: .completed, personalScore: nil)
        for item in [ratedHigh, ratedLow, unrated] { context.insert(item) }

        let average = TasteAnalysisService.averagePersonalScore([ratedHigh, ratedLow, unrated])

        #expect(average == 6.0)
    }

    @MainActor
    @Test func serendipityLevelUsesSharedIntensityBoundaries() {
        let cases: [(Double, SerendipityLevel)] = [
            (0, .conservative),
            (0.32, .conservative),
            (0.33, .balanced),
            (0.65, .balanced),
            (0.66, .adventurous),
            (1, .adventurous),
        ]

        for (intensity, expected) in cases {
            #expect(SerendipityLevel(intensity: intensity) == expected)
        }
    }

    @Test func serendipityCanonicalValuesRoundTrip() {
        for level in SerendipityLevel.allCases {
            #expect(SerendipityLevel(intensity: level.intensity) == level)
        }
        #expect(SerendipityLevel.conservative.intensity == 0)
        #expect(SerendipityLevel.balanced.intensity == 0.5)
        #expect(SerendipityLevel.adventurous.intensity == 1)
    }

    @MainActor
    @Test func recommendationPromptIncludesOnlySelectedSerendipityGuidance() {
        let profile = TasteProfile()
        let service = TasteAnalysisService()
        let guidance = SerendipityLevel.allCases.map(\.promptGuidance)

        for level in SerendipityLevel.allCases {
            let prompt = service.buildRecommendationsPrompt(
                profile: profile,
                existingLibrary: [],
                serendipityLevel: level
            )

            #expect(prompt.contains(level.promptGuidance))
            for otherGuidance in guidance where otherGuidance != level.promptGuidance {
                #expect(!prompt.contains(otherGuidance))
            }
        }
    }

    @MainActor
    @Test func surpriseRequestRequiresAllTenWithoutStandardGuidance() {
        let profile = TasteProfile()
        let service = TasteAnalysisService()
        let request = service.recommendationRequest(
            profile: profile,
            existingLibrary: [],
            serendipityLevel: .conservative,
            surpriseMode: true
        )
        let composed = request.system + "\n" + request.user

        #expect(composed.contains("All 10 recommendations must be serendipitous"))
        for level in SerendipityLevel.allCases {
            #expect(!composed.contains(level.promptGuidance))
        }
    }

    @MainActor
    @Test func recommendationRequestsHonorEveryMediaScopeInBothModes() {
        let profile = TasteProfile()
        let service = TasteAnalysisService()
        let scopes: [MediaType?] = [nil, .book, .movie, .tvShow]

        for surpriseMode in [false, true] {
            for scope in scopes {
                let request = service.recommendationRequest(
                    profile: profile,
                    existingLibrary: [],
                    mediaType: scope,
                    serendipityLevel: .adventurous,
                    surpriseMode: surpriseMode
                )

                if let scope {
                    #expect(request.user.contains("mediaType \"\(scope.rawValue)\" and no other media type"))
                    #expect(!request.user.contains("containing all three mediaType values"))
                } else {
                    #expect(request.user.contains("at least one \"book\", one \"movie\", and one \"tvShow\""))
                }

                if surpriseMode {
                    #expect(request.system.contains("All 10 recommendations must be serendipitous"))
                    for level in SerendipityLevel.allCases {
                        #expect(!request.user.contains(level.promptGuidance))
                    }
                } else {
                    #expect(request.user.contains(SerendipityLevel.adventurous.promptGuidance))
                    #expect(!request.system.contains("SURPRISE ME MODE ACTIVE"))
                }
            }
        }
    }

    @MainActor
    @Test func recommendationPromptSeparatesLibraryAndOutgoingSnapshotExclusions() {
        let profile = TasteProfile()
        let libraryItem = makeItem(
            title: "Library Fixture",
            creator: "Library Creator",
            status: .completed,
            personalScore: 9
        )
        let active = Recommendation()
        active.title = "Active Fixture"
        active.creator = "Active Creator"
        let dismissed = Recommendation()
        dismissed.title = "Dismissed Fixture"
        dismissed.wasDismissed = true
        let added = Recommendation()
        added.title = "Added Fixture"
        added.creator = "Added Creator"
        added.wasAdded = true

        let request = TasteAnalysisService().recommendationRequest(
            profile: profile,
            existingLibrary: [libraryItem],
            excludedRecommendations: [active, dismissed, added],
            mediaType: .book,
            serendipityLevel: .balanced,
            surpriseMode: false
        )

        #expect(request.user.contains("Items already in my library"))
        #expect(request.user.contains("Library Fixture by Library Creator"))
        #expect(request.user.contains("Items just recommended in the current set"))
        #expect(request.user.contains("Active Fixture by Active Creator"))
        #expect(request.user.contains("Dismissed Fixture"))
        #expect(!request.user.contains("Dismissed Fixture by"))
        #expect(request.user.contains("Added Fixture by Added Creator"))
    }

    @MainActor
    @Test func recommendationResponseMappingIsLossyAndScopeSafe() throws {
        func row(_ title: String, _ mediaType: String, malformed: Bool = false) -> String {
            if malformed {
                return #"{"title":"Broken","creator":"Nobody","year":"not a number","mediaType":"book"}"#
            }
            return """
            {
              "title": "\(title)",
              "creator": "Creator",
              "year": 2024,
              "mediaType": "\(mediaType)",
              "genres": ["Drama"],
              "synopsis": "Synopsis.",
              "predictedPersonalScore": 8.5,
              "publicScore": 7.0,
              "serendipityScore": 0.7,
              "isSerendipitous": false,
              "recommendationReason": "Reason.",
              "serendipityExplanation": null
            }
            """
        }

        let response = """
        {"recommendations": [
          \(row("Book Fixture", "book")),
          \(row("Broken", "book", malformed: true)),
          \(row("Movie Fixture", "movie")),
          \(row("TV Fixture", "tvShow")),
          \(row("Unknown Fixture", "podcast"))
        ]}
        """
        let service = TasteAnalysisService()

        let all = try service.recommendations(from: response, mediaType: nil, surpriseMode: false)
        #expect(all.map(\.title) == ["Book Fixture", "Movie Fixture", "TV Fixture"])
        #expect(try service.recommendations(from: response, mediaType: .book, surpriseMode: false).map(\.title) == ["Book Fixture"])
        #expect(try service.recommendations(from: response, mediaType: .movie, surpriseMode: false).map(\.title) == ["Movie Fixture"])
        let surpriseTV = try service.recommendations(from: response, mediaType: .tvShow, surpriseMode: true)
        #expect(surpriseTV.map(\.title) == ["TV Fixture"])
        let everyTVRecommendationIsSerendipitous = surpriseTV.allSatisfy { $0.isSerendipitous }
        #expect(everyTVRecommendationIsSerendipitous)
    }

    @MainActor
    @Test func recommendationResponseRejectsInvalidTopLevelJSON() {
        let service = TasteAnalysisService()

        #expect(throws: ClaudeError.self) {
            try service.recommendations(
                from: #"{"recommendations":[{"title":"Truncated"}"#,
                mediaType: nil,
                surpriseMode: false
            )
        }
    }
}
