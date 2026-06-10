import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var settingsItems: [AppSettings]
    @Environment(\.modelContext) private var context
    @Environment(AppNavigationState.self) private var navigationState

    @State private var tmdbKeyInput = ""
    @State private var anthropicKeyInput = ""
    @State private var googleBooksKeyInput = ""
    @State private var showTMDBKey = false
    @State private var showAnthropicKey = false
    @State private var showGoogleBooksKey = false
    @State private var tmdbValidation: KeyValidationState = .idle
    @State private var anthropicValidation: KeyValidationState = .idle
    @State private var showClearConfirm = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false

    private var settings: AppSettings? { settingsItems.first }

    var body: some View {
        NavigationStack {
            Form {
                // API Keys
                Section {
                    apiKeyRow(
                        label: "TMDB API Key",
                        keyInput: $tmdbKeyInput,
                        showKey: $showTMDBKey,
                        validation: $tmdbValidation,
                        loadAction: { tmdbKeyInput = KeychainService.loadTMDB() ?? "" },
                        saveAction: {
                            KeychainService.saveTMDB(tmdbKeyInput)
                            Task { await validateTMDB() }
                        },
                        validateAction: { Task { await validateTMDB() } }
                    )
                    apiKeyRow(
                        label: "Anthropic API Key",
                        keyInput: $anthropicKeyInput,
                        showKey: $showAnthropicKey,
                        validation: $anthropicValidation,
                        loadAction: { anthropicKeyInput = KeychainService.loadAnthropic() ?? "" },
                        saveAction: {
                            KeychainService.saveAnthropic(anthropicKeyInput)
                            Task { await validateAnthropic() }
                        },
                        validateAction: { Task { await validateAnthropic() } }
                    )
                    simpleKeyRow(
                        label: "Google Books API Key",
                        keyInput: $googleBooksKeyInput,
                        showKey: $showGoogleBooksKey,
                        loadAction: { googleBooksKeyInput = KeychainService.loadGoogleBooks() ?? "" },
                        saveAction: { KeychainService.saveGoogleBooks(googleBooksKeyInput) }
                    )
                } header: {
                    Text("API Keys")
                } footer: {
                    Text("Keys are stored securely in the iOS Keychain. Google Books works without a key, but adding one raises your import rate limits.")
                }

                // Display
                if let s = settings {
                    Section("Display") {
                        Toggle("Show Public Scores", isOn: Binding(
                            get: { s.showPublicScores },
                            set: { s.showPublicScores = $0 }
                        ))
                        Picker("Default Media Type", selection: Binding(
                            get: { s.defaultMediaType },
                            set: { s.defaultMediaType = $0 }
                        )) {
                            ForEach(MediaType.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Serendipity")
                                Spacer()
                                Text(serendipityLabel(s.serendipityIntensity))
                                    .font(.caption)
                                    .foregroundStyle(KonomiTheme.secondary)
                            }
                            Slider(value: Binding(
                                get: { s.serendipityIntensity },
                                set: { s.serendipityIntensity = $0 }
                            ), in: 0...1)
                            .tint(KonomiTheme.serendipity)
                            HStack {
                                Text("Conservative")
                                    .font(.caption)
                                    .foregroundStyle(KonomiTheme.secondary)
                                Spacer()
                                Text("Adventurous")
                                    .font(.caption)
                                    .foregroundStyle(KonomiTheme.secondary)
                            }
                        }
                    } header: {
                        Text("Recommendations")
                    } footer: {
                        Text("Controls how far Claude strays from your established taste.")
                    }
                }

                // Data
                Section("Data") {
                    Button {
                        navigationState.showGoodreadsImport = true
                    } label: {
                        Label("Import from Goodreads", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        exportLibrary()
                    } label: {
                        Label("Export Library as CSV", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear All Recommendations", systemImage: "trash")
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("Konomi")
                        Spacer()
                        Text("Version 1.0")
                            .foregroundStyle(KonomiTheme.secondary)
                    }
                    HStack {
                        Text("好み")
                        Spacer()
                        Text("Taste in Japanese")
                            .foregroundStyle(KonomiTheme.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                tmdbKeyInput = KeychainService.loadTMDB() ?? ""
                anthropicKeyInput = KeychainService.loadAnthropic() ?? ""
                googleBooksKeyInput = KeychainService.loadGoogleBooks() ?? ""
            }
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
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    // MARK: - API Key row builder

    @ViewBuilder
    private func apiKeyRow(
        label: String,
        keyInput: Binding<String>,
        showKey: Binding<Bool>,
        validation: Binding<KeyValidationState>,
        loadAction: @escaping () -> Void,
        saveAction: @escaping () -> Void,
        validateAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.medium))
            HStack {
                Group {
                    if showKey.wrappedValue {
                        TextField("Paste key...", text: keyInput)
                    } else {
                        SecureField("Paste key...", text: keyInput)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())

                Button {
                    showKey.wrappedValue.toggle()
                } label: {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                        .foregroundStyle(KonomiTheme.secondary)
                }

                Button("Save") {
                    saveAction()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(KonomiTheme.primary)
            }

            HStack(spacing: 6) {
                switch validation.wrappedValue {
                case .idle:
                    EmptyView()
                case .validating:
                    ProgressView().scaleEffect(0.7)
                    Text("Validating...")
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.secondary)
                case .valid:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KonomiTheme.success)
                    Text("Valid key")
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.success)
                case .invalid(let msg):
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(hex: "#FF453A"))
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#FF453A"))
                }
            }
            .frame(height: 20)
        }
        .onAppear { loadAction() }
    }

    @ViewBuilder
    private func simpleKeyRow(
        label: String,
        keyInput: Binding<String>,
        showKey: Binding<Bool>,
        loadAction: @escaping () -> Void,
        saveAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.medium))
            HStack {
                Group {
                    if showKey.wrappedValue {
                        TextField("Paste key...", text: keyInput)
                    } else {
                        SecureField("Paste key...", text: keyInput)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())

                Button {
                    showKey.wrappedValue.toggle()
                } label: {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                        .foregroundStyle(KonomiTheme.secondary)
                }

                Button("Save") {
                    saveAction()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(KonomiTheme.primary)
            }

            Text("Optional for Goodreads import fallback metadata.")
                .font(.caption)
                .foregroundStyle(KonomiTheme.secondary)
        }
        .onAppear { loadAction() }
    }

    // MARK: - Validation

    @MainActor
    private func validateTMDB() async {
        tmdbValidation = .validating
        do {
            let valid = try await TMDBService.validateKey(tmdbKeyInput)
            tmdbValidation = valid ? .valid : .invalid("Key rejected by TMDB")
        } catch {
            tmdbValidation = .invalid(error.localizedDescription)
        }
    }

    @MainActor
    private func validateAnthropic() async {
        anthropicValidation = .validating
        do {
            _ = try await ClaudeService.sendWithSystem(
                "You are a test assistant.",
                user: "Reply with exactly: OK",
                maxTokens: 10
            )
            anthropicValidation = .valid
        } catch {
            anthropicValidation = .invalid(error.localizedDescription)
        }
    }

    // MARK: - Data actions

    private func clearRecommendations() {
        do {
            let recs = try context.fetch(FetchDescriptor<Recommendation>())
            for r in recs { context.delete(r) }
            try context.save()
        } catch {}
    }

    private func exportLibrary() {
        do {
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.sortBy = [SortDescriptor(\.dateAdded, order: .reverse)]
            let items = try context.fetch(descriptor)
            var csv = "Title,Creator,Year,Type,Status,Your Score,Public Score,Date Added\n"
            let df = DateFormatter()
            df.dateStyle = .short
            for item in items {
                let title = item.title.replacingOccurrences(of: ",", with: ";")
                let creator = item.creator.replacingOccurrences(of: ",", with: ";")
                let year = item.year.map(String.init) ?? ""
                let type = item.mediaType.displayName
                let status = item.status.displayName
                let personal = item.personalScore.map(String.init) ?? ""
                let pub = item.publicScore.map { String(format: "%.1f", $0) } ?? ""
                let date = df.string(from: item.dateAdded)
                let row = [title, creator, year, type, status, personal, pub, date].joined(separator: ",")
                csv += row + "\n"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("konomi_library.csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showShareSheet = true
        } catch {}
    }

    private func serendipityLabel(_ value: Double) -> String {
        switch value {
        case 0..<0.33: return "Conservative"
        case 0.33..<0.66: return "Balanced"
        default: return "Adventurous"
        }
    }
}

// MARK: - Key validation state

enum KeyValidationState {
    case idle
    case validating
    case valid
    case invalid(String)
}

// MARK: - Share sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
