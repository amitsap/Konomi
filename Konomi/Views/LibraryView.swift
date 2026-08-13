import SwiftUI
import SwiftData
import UIKit

struct LibraryView: View {
    @Query(sort: \MediaItem.dateAdded, order: .reverse) private var allItems: [MediaItem]
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var context
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedType: MediaType? = nil
    @State private var selectedStatus: MediaStatus? = nil
    @State private var searchText = ""
    @State private var sortOrder: LibrarySortOrder = .dateAdded
    @State private var quickRateItem: MediaItem?
    @State private var hasTMDBKey = false
    @State private var deletionNotice: LibraryDeletionNotice?
    @State private var errorMessage: String?
    @State private var showError = false

    private var deletionExpiryKey: UndoExpiryKey {
        UndoExpiryKey(
            token: deletionNotice?.token,
            isVoiceOverEnabled: isVoiceOverEnabled,
            isSwitchControlEnabled: isSwitchControlEnabled,
            isUntimed: deletionNotice?.isUntimed ?? false
        )
    }

    private var noticeTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private var prewarmSignature: String {
        filteredItems
            .filter { $0.mediaType == .book && $0.coverImageData == nil && ($0.coverURLString == nil || $0.coverURLString?.isEmpty == true) }
            .prefix(24)
            .map { "\($0.id.uuidString)-\($0.title)-\($0.creator)" }
            .joined(separator: "|")
    }

    var filteredItems: [MediaItem] {
        var items = allItems

        if let type = selectedType {
            items = items.filter { $0.mediaType == type }
        }
        if let status = selectedStatus {
            items = items.filter { $0.status == status }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            items = items.filter {
                $0.title.lowercased().contains(q) || $0.creator.lowercased().contains(q)
            }
        }

        switch sortOrder {
        case .dateAdded: break // already sorted by query
        case .title: items.sort { $0.title < $1.title }
        case .personalScore: items.sort { ($0.personalScore ?? 0) > ($1.personalScore ?? 0) }
        case .year: items.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .publicScore: items.sort { ($0.publicScore ?? 0) > ($1.publicScore ?? 0) }
        }

        return items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if allItems.isEmpty {
                    trueEmptyState
                } else {
                    filterBar

                    Divider()

                    if filteredItems.isEmpty {
                        noMatchesState
                    } else {
                        List {
                            ForEach(filteredItems) { item in
                                NavigationLink(value: item) {
                                    MediaCard(
                                        item: item,
                                        style: .list,
                                        showPublic: settings.first?.showPublicScores ?? true
                                    )
                                }
                                .accessibilityIdentifier("library-row-\(item.title)")
                                .listRowBackground(KonomiTheme.canvas)
                                .listRowSeparatorTint(KonomiTheme.hairline)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        item.isFavorite.toggle()
                                    } label: {
                                        Label(item.isFavorite ? "Unfavorite" : "Favorite",
                                              systemImage: item.isFavorite ? "heart.slash" : "heart.fill")
                                    }
                                    .tint(KonomiTheme.persimmon)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        quickRateItem = item
                                    } label: {
                                        Label("Quick Rate", systemImage: "star")
                                    }
                                    .tint(KonomiTheme.persimmon)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .background(KonomiTheme.canvas)
            .safeAreaInset(edge: .bottom) {
                if let notice = deletionNotice {
                    UndoNoticeView(
                        systemImage: "trash.fill",
                        message: "Deleted “\(notice.title)”",
                        messageAccessibilityLabel: "Deleted \(notice.title)",
                        actionAccessibilityLabel: "Undo delete \(notice.title)",
                        onUndo: restoreDeletedItem
                    )
                    .transition(noticeTransition)
                }
            }
            .animation(
                reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.25),
                value: deletionNotice?.token
            )
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search titles, creators...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            navigationState.showAddSheet = true
                        } label: {
                            Label("Add Media", systemImage: "plus")
                        }

                        Button {
                            navigationState.showQuickSetup = true
                        } label: {
                            Label("Quick Setup", systemImage: "checklist")
                        }

                        Button {
                            navigationState.showGoodreadsImport = true
                        } label: {
                            Label("Import from Goodreads", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Media")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                if sortOrder == order {
                                    Label(order.displayName, systemImage: "checkmark")
                                } else {
                                    Text(order.displayName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort Library")
                    .accessibilityValue(sortOrder.displayName)
                }
            }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
            }
            .sheet(item: $quickRateItem) { item in
                QuickRateSheet(item: item)
            }
            .alert("Library Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Konomi couldn't complete that Library action.")
            }
            .task(id: deletionExpiryKey) {
                await expireDeletionNoticeIfNeeded()
            }
            .task(id: prewarmSignature) {
                await BookCoverService.prewarmMissingCovers(for: filteredItems, in: context)
            }
            .onAppear {
                refreshTMDBAvailability()
            }
            .onChange(of: navigationState.selectedTab) { _, selectedTab in
                if selectedTab == .library {
                    refreshTMDBAvailability()
                }
            }
        }
    }

    private func delete(_ item: MediaItem) {
        let title = item.title
        do {
            let snapshot = try MediaItemDeletionStore.delete(item, in: context)
            let notice = LibraryDeletionNotice(snapshot: snapshot)
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                deletionNotice = notice
            }
            UIAccessibility.post(
                notification: .announcement,
                argument: "Deleted \(title). Undo available."
            )
        } catch {
            errorMessage = "Konomi couldn't delete \(title). Your earlier changes were left intact."
            showError = true
        }
    }

    private func restoreDeletedItem() {
        guard let notice = deletionNotice else { return }
        do {
            _ = try MediaItemDeletionStore.restore(notice.snapshot, in: context)
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                deletionNotice = nil
            }
        } catch {
            if deletionNotice?.token == notice.token {
                deletionNotice?.isUntimed = true
            }
            errorMessage = "Konomi couldn't restore \(notice.title). Undo is still available; try again."
            showError = true
        }
    }

    private func expireDeletionNoticeIfNeeded() async {
        guard let notice = deletionNotice,
              !isVoiceOverEnabled,
              !isSwitchControlEnabled,
              !notice.isUntimed else {
            return
        }

        do {
            try await Task.sleep(for: .seconds(6))
        } catch {
            return
        }
        guard !Task.isCancelled, deletionNotice?.token == notice.token else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
            deletionNotice = nil
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterMenu(
                    title: "Media",
                    value: selectedType?.pluralName ?? "All",
                    systemImage: selectedType?.icon ?? "square.grid.2x2"
                ) {
                    Button {
                        selectedType = nil
                    } label: {
                        if selectedType == nil {
                            Label("All Media", systemImage: "checkmark")
                        } else {
                            Text("All Media")
                        }
                    }

                    ForEach(MediaType.allCases, id: \.self) { type in
                        Button {
                            selectedType = type
                        } label: {
                            if selectedType == type {
                                Label(type.pluralName, systemImage: "checkmark")
                            } else {
                                Text(type.pluralName)
                            }
                        }
                    }
                }

                filterMenu(
                    title: "Status",
                    value: selectedStatus?.displayName ?? "All",
                    systemImage: "line.3.horizontal.decrease.circle"
                ) {
                    Button {
                        selectedStatus = nil
                    } label: {
                        if selectedStatus == nil {
                            Label("All Statuses", systemImage: "checkmark")
                        } else {
                            Text("All Statuses")
                        }
                    }

                    ForEach(MediaStatus.allCases, id: \.self) { status in
                        Button {
                            selectedStatus = status
                        } label: {
                            if selectedStatus == status {
                                Label(status.displayName, systemImage: "checkmark")
                            } else {
                                Text(status.displayName)
                            }
                        }
                    }
                }

                if selectedType != nil || selectedStatus != nil {
                    Button {
                        selectedType = nil
                        selectedStatus = nil
                    } label: {
                        Label("Clear", systemImage: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(KonomiTheme.surface)
                            .clipShape(Capsule())
                            .overlay { Capsule().stroke(KonomiTheme.hairline, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Filters")
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 52)
        .background(KonomiTheme.canvas)
    }

    private func filterMenu<Content: View>(
        title: String,
        value: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KonomiTheme.persimmon)
                Text("\(title) · \(value)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KonomiTheme.ink)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(KonomiTheme.inkSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(KonomiTheme.surface)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(KonomiTheme.hairline, lineWidth: 1) }
        }
        .accessibilityLabel("\(title) filter")
        .accessibilityValue(value)
    }

    private var trueEmptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                ContentUnavailableView(
                    "Your library is ready for a first title",
                    systemImage: "books.vertical",
                    description: Text("Add media directly, use Quick Setup, or import your Goodreads history.")
                )

                VStack(spacing: 14) {
                    Button {
                        navigationState.showAddSheet = true
                    } label: {
                        Label("Add Media", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(KonomiTheme.persimmon)
                            .foregroundStyle(KonomiTheme.onPersimmon)
                            .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.controlRadius))
                    }

                    Button {
                        openQuickSetupOrSettings()
                    } label: {
                        Label(
                            hasTMDBKey ? "Quick Setup" : "Set Up TMDB for Quick Setup",
                            systemImage: hasTMDBKey ? "checklist" : "gearshape"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KonomiTheme.persimmon)
                    }

                    Button {
                        navigationState.showGoodreadsImport = true
                    } label: {
                        Label("Import from Goodreads", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KonomiTheme.persimmon)
                    }
                }
                .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
    }

    private var noMatchesState: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Nothing matches \(activeCriteriaDescription). Try another search or clear the filters.")
        } actions: {
            Button("Clear Filters") {
                clearAllCriteria()
            }
            .buttonStyle(.borderedProminent)
            .tint(KonomiTheme.persimmon)
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private var activeCriteriaDescription: String {
        var criteria: [String] = []
        if !searchText.isEmpty { criteria.append("“\(searchText)”") }
        if let selectedType { criteria.append(selectedType.pluralName) }
        if let selectedStatus { criteria.append(selectedStatus.displayName) }
        return criteria.isEmpty ? "the current criteria" : criteria.joined(separator: ", ")
    }

    private func clearAllCriteria() {
        searchText = ""
        selectedType = nil
        selectedStatus = nil
    }

    private func refreshTMDBAvailability() {
        hasTMDBKey = KeychainService.hasUsableTMDBKey()
    }

    private func openQuickSetupOrSettings() {
        let isConfigured = KeychainService.hasUsableTMDBKey()
        hasTMDBKey = isConfigured
        if isConfigured {
            navigationState.showQuickSetup = true
        } else {
            navigationState.navigateToTaste(.connections)
        }
    }
}

private struct LibraryDeletionNotice {
    let token = UUID()
    let snapshot: MediaItemDeletionSnapshot
    var isUntimed = false

    var title: String { snapshot.title }
}

private struct UndoExpiryKey: Hashable {
    let token: UUID?
    let isVoiceOverEnabled: Bool
    let isSwitchControlEnabled: Bool
    let isUntimed: Bool
}

enum LibrarySortOrder: CaseIterable {
    case dateAdded, title, personalScore, year, publicScore

    var displayName: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .title: return "Title"
        case .personalScore: return "Your Score"
        case .year: return "Year"
        case .publicScore: return "Public Score"
        }
    }
}
