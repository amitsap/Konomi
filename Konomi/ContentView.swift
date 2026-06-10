import SwiftUI

struct ContentView: View {
    @Environment(AppNavigationState.self) private var navigationState

    var body: some View {
        @Bindable var navigationState = navigationState

        TabView(selection: $navigationState.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: KonomiTab.home) {
                HomeView()
            }
            Tab("Library", systemImage: "books.vertical.fill", value: KonomiTab.library) {
                LibraryView()
            }
            Tab("For You", systemImage: "sparkles", value: KonomiTab.recommendations) {
                RecommendationsView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: KonomiTab.profile) {
                ProfileTabView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: KonomiTab.settings) {
                SettingsView()
            }
        }
        .overlay(alignment: .bottom) {
            addButton
        }
        .sheet(isPresented: $navigationState.showAddSheet) {
            AddMediaView()
        }
        .sheet(isPresented: $navigationState.showQuickSetup) {
            NavigationStack {
                QuickSetupView()
            }
        }
        .sheet(isPresented: $navigationState.showGoodreadsImport) {
            NavigationStack {
                GoodreadsImportView()
            }
        }
    }

    private var addButton: some View {
        Button {
            navigationState.showAddSheet = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(KonomiTheme.primary)
                .background(Circle().fill(.white).padding(4))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .offset(y: -50)
    }
}

// Profile tab contains both TasteProfile and Statistics
struct ProfileTabView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    TasteProfileView()
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Your Taste Profile", systemImage: "brain")
                }

                NavigationLink {
                    StatisticsView()
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Statistics", systemImage: "chart.bar.fill")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

enum KonomiTab: Hashable {
    case home, library, recommendations, profile, settings
}
