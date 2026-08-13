import SwiftUI
import SwiftData

@main
struct KonomiApp: App {
    let tasteService = TasteAnalysisService()
    @State private var navigationState = AppNavigationState()
    @State private var persistenceState = PersistenceState()

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = persistenceState.container {
                    ContentView()
                        .modelContainer(container)
                } else {
                    PersistenceRecoveryView(state: persistenceState)
                }
            }
                .konomiTheme()
                .environment(tasteService)
                .environment(navigationState)
        }
    }
}
