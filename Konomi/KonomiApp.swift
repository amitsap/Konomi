import SwiftUI
import SwiftData

@main
struct KonomiApp: App {
    let container: ModelContainer
    let tasteService = TasteAnalysisService()
    @State private var navigationState = AppNavigationState()

    init() {
        let schema = Schema([
            MediaItem.self,
            DetailedRating.self,
            TasteProfile.self,
            Recommendation.self,
            AppSettings.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            let ctx = container.mainContext
            let existing = try ctx.fetch(FetchDescriptor<AppSettings>())
            if existing.isEmpty {
                ctx.insert(AppSettings())
                try ctx.save()
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .fontDesign(.rounded)
                .konomiTheme()
        }
        .modelContainer(container)
        .environment(tasteService)
        .environment(navigationState)
    }
}
