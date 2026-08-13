import Foundation
import Observation

@Observable
final class AppNavigationState {
    var selectedTab: KonomiTab = .taste
    var tastePath: [TasteRoute] = []
    var showAddSheet = false
    var showGoodreadsImport = false
    var showQuickSetup = false

    func navigateToTaste(_ route: TasteRoute) {
        selectedTab = .taste
        tastePath = [route]
    }
}

enum TasteRoute: Hashable {
    case media(MediaItem)
    case profile
    case insights
    case settings
    case connections
}
