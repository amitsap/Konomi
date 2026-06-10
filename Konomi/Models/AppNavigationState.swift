import Foundation
import Observation

@Observable
final class AppNavigationState {
    var selectedTab: KonomiTab = .home
    var showAddSheet = false
    var showGoodreadsImport = false
    var showQuickSetup = false
}
