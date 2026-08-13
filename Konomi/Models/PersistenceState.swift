import Foundation
import Observation
import SwiftData

@Observable
final class PersistenceState {
    typealias ContainerFactory = () throws -> ModelContainer

    private let factory: ContainerFactory
    private var shouldSimulateFailure: Bool

    private(set) var container: ModelContainer?
    private(set) var failureDetails = ""
    private(set) var isRetrying = false

    init(
        factory: @escaping ContainerFactory = { try PersistenceState.makeDefaultContainer() },
        simulateFailureOnce: Bool? = nil
    ) {
        self.factory = factory
        #if DEBUG
        shouldSimulateFailure = simulateFailureOnce
            ?? ProcessInfo.processInfo.arguments.contains("-KonomiSimulatePersistenceFailureOnce")
        #else
        shouldSimulateFailure = false
        #endif
        attemptLoad()
    }

    private static func makeDefaultContainer() throws -> ModelContainer {
        #if DEBUG
        if let scenario = UITestScenario(arguments: ProcessInfo.processInfo.arguments) {
            let configuration = ModelConfiguration(
                schema: PersistenceBootstrap.schema,
                isStoredInMemoryOnly: true
            )
            let container = try PersistenceBootstrap.makeContainer(configuration: configuration)
            try seedUITestData(scenario, in: container.mainContext)
            return container
        }
        #endif
        return try PersistenceBootstrap.makeContainer()
    }

    #if DEBUG
    private enum UITestScenario: String {
        case empty
        case building
        case ready
        case mature

        init?(arguments: [String]) {
            guard let flagIndex = arguments.firstIndex(of: "-KonomiUITestScenario"),
                  arguments.indices.contains(flagIndex + 1)
            else { return nil }
            self.init(rawValue: arguments[flagIndex + 1])
        }
    }

    private static func seedUITestData(_ scenario: UITestScenario, in context: ModelContext) throws {
        guard scenario != .empty else {
            try context.save()
            return
        }

        let completedCount = scenario == .building ? 3 : 5
        for index in 1...completedCount {
            let item = MediaItem()
            item.title = index == 1 ? "UI Test Library Item" : "UI Test Rated Item \(index)"
            item.creator = index.isMultiple(of: 2) ? "A. Creator" : "B. Creator"
            item.mediaType = MediaType.allCases[index % MediaType.allCases.count]
            item.status = .completed
            item.personalScore = 5 + index
            item.publicScore = 6.8 + Double(index) * 0.3
            item.genres = index.isMultiple(of: 2) ? ["Drama", "Mystery"] : ["Fantasy", "Adventure"]
            item.dateCompleted = Date(timeIntervalSince1970: 1_786_000_000 + Double(index * 18_000))
            context.insert(item)
        }

        if scenario == .building {
            let item = MediaItem()
            item.title = "UI Test In Progress"
            item.creator = "Current Creator"
            item.status = .inProgress
            item.dateStarted = Date(timeIntervalSince1970: 1_735_689_600)
            context.insert(item)
        }

        if scenario == .mature {
            let profile = TasteProfile()
            profile.tasteDescription = "You gravitate toward emotionally precise stories with vivid worlds and earned surprises."
            profile.favoriteGenres = ["Drama", "Fantasy", "Mystery"]
            profile.favoriteCreators = ["A. Creator", "B. Creator"]
            profile.favoriteThemes = ["Found family", "Transformation"]
            profile.strongPatterns = ["Character-led stories", "Atmospheric settings"]
            profile.avoidPatterns = ["Unresolved endings"]
            profile.totalCompleted = completedCount
            profile.averagePersonalScore = 8
            profile.lastUpdated = Date(timeIntervalSince1970: 1_786_200_000)
            context.insert(profile)

            for (index, title) in ["UI Test Recommendation", "UI Test Second Recommendation"].enumerated() {
                let recommendation = Recommendation()
                recommendation.title = title
                recommendation.creator = "Recommendation Creator \(index + 1)"
                recommendation.mediaType = index == 0 ? .book : .movie
                recommendation.predictedPersonalScore = 8.4
                recommendation.recommendationReason = "Seeded for reversible-action UI verification."
                recommendation.generatedDate = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
                context.insert(recommendation)
            }
        }
        try context.save()
    }
    #endif

    func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        await Task.yield()
        attemptLoad()
        isRetrying = false
    }

    private func attemptLoad() {
        do {
            #if DEBUG
            if shouldSimulateFailure {
                shouldSimulateFailure = false
                throw PersistenceStateError.simulatedFailure
            }
            #endif
            container = try factory()
            failureDetails = ""
        } catch {
            container = nil
            failureDetails = error.localizedDescription
        }
    }
}

#if DEBUG
private enum PersistenceStateError: LocalizedError {
    case simulatedFailure

    var errorDescription: String? {
        "Simulated persistence failure for UI testing."
    }
}
#endif
