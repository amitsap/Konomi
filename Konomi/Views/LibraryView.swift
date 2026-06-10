import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \MediaItem.dateAdded, order: .reverse) private var allItems: [MediaItem]
    @Environment(\.modelContext) private var context
    @Environment(AppNavigationState.self) private var navigationState

    @State private var selectedType: MediaType? = nil
    @State private var selectedStatus: MediaStatus? = nil
    @State private var searchText = ""
    @State private var sortOrder: LibrarySortOrder = .dateAdded
    @State private var selectedItem: MediaItem?

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
                filterBar

                Divider()

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item, style: .list)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    context.delete(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    item.isFavorite.toggle()
                                } label: {
                                    Label(item.isFavorite ? "Unfavorite" : "Favorite",
                                          systemImage: item.isFavorite ? "heart.slash" : "heart.fill")
                                }
                                .tint(KonomiTheme.primary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(KonomiTheme.background)
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
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                Label(order.displayName, systemImage: sortOrder == order ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
            }
            .task(id: prewarmSignature) {
                await BookCoverService.prewarmMissingCovers(for: filteredItems, in: context)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            filterMenu(
                title: "Media",
                value: selectedType?.pluralName ?? "All",
                systemImage: selectedType?.icon ?? "square.grid.2x2"
            ) {
                Button {
                    selectedType = nil
                } label: {
                    Label("All Media", systemImage: selectedType == nil ? "checkmark" : "")
                }

                ForEach(MediaType.allCases, id: \.self) { type in
                    Button {
                        selectedType = type
                    } label: {
                        Label(type.pluralName, systemImage: selectedType == type ? "checkmark" : "")
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
                    Label("All Statuses", systemImage: selectedStatus == nil ? "checkmark" : "")
                }

                ForEach(MediaStatus.allCases, id: \.self) { status in
                    Button {
                        selectedStatus = status
                    } label: {
                        Label(status.displayName, systemImage: selectedStatus == status ? "checkmark" : "")
                    }
                }
            }

            if selectedType != nil || selectedStatus != nil {
                Button {
                    selectedType = nil
                    selectedStatus = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KonomiTheme.secondary)
                        .frame(width: 34, height: 34)
                        .background(KonomiTheme.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(KonomiTheme.background)
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
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KonomiTheme.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.secondary)
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KonomiTheme.text)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KonomiTheme.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(KonomiTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "No items found",
                systemImage: "books.vertical",
                description: Text("Add something to your library to get started")
            )

            VStack(spacing: 12) {
                Button {
                    navigationState.showGoodreadsImport = true
                } label: {
                    Label("Import from Goodreads", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 14)
                        .background(KonomiTheme.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button("Add Manually") {
                    navigationState.showAddSheet = true
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 20)
    }
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
