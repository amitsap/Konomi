import SwiftUI

struct ContentView: View {
    @Environment(AppNavigationState.self) private var navigationState

    var body: some View {
        @Bindable var navigationState = navigationState

        TabView(selection: $navigationState.selectedTab) {
            Tab("Taste", systemImage: "heart.text.square.fill", value: KonomiTab.taste) {
                TasteView()
            }
            Tab("Library", systemImage: "books.vertical", value: KonomiTab.library) {
                LibraryView()
            }
            Tab("Discover", systemImage: "sparkles", value: KonomiTab.discover) {
                RecommendationsView()
            }
        }
        .sheet(isPresented: $navigationState.showAddSheet) {
            AddMediaView()
        }
        .sheet(isPresented: $navigationState.showQuickSetup) {
            NavigationStack { QuickSetupView() }
        }
        .sheet(isPresented: $navigationState.showGoodreadsImport) {
            NavigationStack { GoodreadsImportView() }
        }
    }
}

enum KonomiTab: Hashable {
    case taste
    case library
    case discover
}
