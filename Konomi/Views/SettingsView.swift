import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var settingsItems: [AppSettings]
    @Environment(\.modelContext) private var context
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showClearConfirm = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var hasAnthropicKey = false
    @State private var hasTMDBKey = false

    private var settings: AppSettings? { settingsItems.first }
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                NavigationLink(value: TasteRoute.connections) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Connections", systemImage: "key.horizontal")
                            .font(.headline)
                        Text(connectionSummary)
                            .font(.subheadline)
                            .foregroundStyle(KonomiTheme.inkSecondary)
                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 6) {
                                    connectionStatus(name: "Anthropic", connected: hasAnthropicKey)
                                    connectionStatus(name: "TMDB", connected: hasTMDBKey)
                                }
                            } else {
                                HStack(spacing: 12) {
                                    connectionStatus(name: "Anthropic", connected: hasAnthropicKey)
                                    connectionStatus(name: "TMDB", connected: hasTMDBKey)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .accessibilityLabel("Connections")
                .accessibilityValue(connectionSummary)
            }

            if let settings {
                Section("Preferences") {
                    Toggle("Show Public Scores", isOn: Binding(
                        get: { settings.showPublicScores },
                        set: { settings.showPublicScores = $0 }
                    ))
                    Picker("Default Media Type", selection: Binding(
                        get: { settings.defaultMediaType },
                        set: { settings.defaultMediaType = $0 }
                    )) {
                        ForEach(MediaType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    Picker("Discovery Style", selection: Binding(
                        get: { settings.serendipityLevel },
                        set: { settings.serendipityIntensity = $0.intensity }
                    )) {
                        ForEach(SerendipityLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(KonomiTheme.tasteViolet)
                }
            }

            Section("Library & Data") {
                Button {
                    navigationState.showGoodreadsImport = true
                } label: {
                    Label("Import from Goodreads", systemImage: "square.and.arrow.down")
                }
                Button(action: exportLibrary) {
                    Label("Export Library as CSV", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Clear All Recommendations", systemImage: "trash")
                }
            }

            Section("About") {
                HStack(spacing: 16) {
                    TasteContourView().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Konomi · 好み").font(.headline)
                        Text("Personal taste, in Japanese")
                            .font(.subheadline)
                            .foregroundStyle(KonomiTheme.inkSecondary)
                    }
                }
                LabeledContent("Version", value: appVersion)
                Text("Your library, ratings, and profile are stored locally on this device. API keys stay in the iOS Keychain.")
                    .font(.footnote)
                    .foregroundStyle(KonomiTheme.inkSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(KonomiTheme.canvas)
        .navigationTitle("Settings")
        .onAppear(perform: refreshConnectionSummary)
        .confirmationDialog(
            "Clear all recommendations?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { clearRecommendations() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL { ShareSheet(activityItems: [exportURL]) }
        }
    }

    private var connectionSummary: String {
        switch (hasAnthropicKey, hasTMDBKey) {
        case (true, true): "Anthropic and TMDB connected"
        case (false, true): "Anthropic needed"
        case (true, false): "TMDB needed"
        case (false, false): "Anthropic and TMDB need attention"
        }
    }

    private func connectionStatus(name: String, connected: Bool) -> some View {
        Label("\(name) \(connected ? "connected" : "needed")", systemImage: connected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(connected ? KonomiTheme.success : .orange)
    }

    private func refreshConnectionSummary() {
        hasAnthropicKey = KeychainService.hasUsableAnthropicKey()
        hasTMDBKey = KeychainService.hasUsableTMDBKey()
    }

    private func clearRecommendations() {
        do {
            let recommendations = try context.fetch(FetchDescriptor<Recommendation>())
            for recommendation in recommendations { context.delete(recommendation) }
            try context.save()
        } catch {}
    }

    private func exportLibrary() {
        do {
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.sortBy = [SortDescriptor(\.dateAdded, order: .reverse)]
            let items = try context.fetch(descriptor)
            var csv = "Title,Creator,Year,Type,Status,Your Score,Public Score,Date Added\n"
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            for item in items {
                let values = [
                    item.title.replacingOccurrences(of: ",", with: ";"),
                    item.creator.replacingOccurrences(of: ",", with: ";"),
                    item.year.map(String.init) ?? "",
                    item.mediaType.displayName,
                    item.status.displayName,
                    item.personalScore.map(String.init) ?? "",
                    item.publicScore.map { String(format: "%.1f", $0) } ?? "",
                    formatter.string(from: item.dateAdded)
                ]
                csv += values.joined(separator: ",") + "\n"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("konomi_library.csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showShareSheet = true
        } catch {}
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
