import SwiftUI

struct ConnectionsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var anthropic = KeyEntryState()
    @State private var tmdb = KeyEntryState()
    @State private var googleBooks = KeyEntryState()
    @State private var pendingRemoval: ConnectionService?
    @State private var anthropicValidationTask: Task<Void, Never>?
    @State private var tmdbValidationTask: Task<Void, Never>?

    var body: some View {
        Form {
            serviceSection(.anthropic, entry: $anthropic)
            serviceSection(.tmdb, entry: $tmdb)
            serviceSection(.googleBooks, entry: $googleBooks)
        }
        .scrollContentBackground(.hidden)
        .background(KonomiTheme.canvas)
        .navigationTitle("Connections")
        .onAppear(perform: loadKeys)
        .onDisappear(perform: cancelValidationTasks)
        .confirmationDialog(
            pendingRemoval.map { "Remove \($0.title) key?" } ?? "Remove key?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingRemoval {
                Button("Remove Key", role: .destructive) { remove(pendingRemoval) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let pendingRemoval { Text(pendingRemoval.removalConsequence) }
        }
    }

    @ViewBuilder
    private func serviceSection(_ service: ConnectionService, entry: Binding<KeyEntryState>) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label(service.title, systemImage: service.symbol)
                    .font(.headline)
                Text(service.purpose)
                    .font(.subheadline)
                    .foregroundStyle(KonomiTheme.inkSecondary)

                Group {
                    if entry.wrappedValue.revealed {
                        TextField(service.placeholder, text: entry.input)
                    } else {
                        SecureField(service.placeholder, text: entry.input)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .submitLabel(.done)
                .onSubmit {
                    if canSave(entry.wrappedValue) { save(service) }
                }

                keyControls(service, entry: entry)

                connectionState(entry.wrappedValue)

                if !entry.wrappedValue.original.isEmpty {
                    Button("Remove Key", role: .destructive) {
                        pendingRemoval = service
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func keyControls(_ service: ConnectionService, entry: Binding<KeyEntryState>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                Button {
                    entry.wrappedValue.revealed.toggle()
                } label: {
                    Text(entry.wrappedValue.revealed ? "Hide Key" : "Show Key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    save(service)
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave(entry.wrappedValue))
            }
        } else {
            HStack(spacing: 12) {
                Button(entry.wrappedValue.revealed ? "Hide Key" : "Show Key") {
                    entry.wrappedValue.revealed.toggle()
                }
                .buttonStyle(.bordered)

                Button("Save") { save(service) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave(entry.wrappedValue))
            }
        }
    }

    @ViewBuilder
    private func connectionState(_ entry: KeyEntryState) -> some View {
        switch entry.validation {
        case .idle:
            Label(entry.original.isEmpty ? "Not set" : "Connected", systemImage: entry.original.isEmpty ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(entry.original.isEmpty ? KonomiTheme.inkSecondary : KonomiTheme.success)
        case .validating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(KonomiTheme.inkSecondary)
            }
        case .valid:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(KonomiTheme.success)
        case .invalid(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func canSave(_ entry: KeyEntryState) -> Bool {
        let trimmed = entry.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.original else { return false }
        if case .validating = entry.validation { return false }
        return true
    }

    private func loadKeys() {
        anthropic = KeyEntryState(stored: KeychainService.loadAnthropic())
        tmdb = KeyEntryState(stored: KeychainService.loadTMDB())
        googleBooks = KeyEntryState(stored: KeychainService.loadGoogleBooks())
    }

    private func save(_ service: ConnectionService) {
        switch service {
        case .anthropic:
            let value = anthropic.input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != anthropic.original else { return }
            KeychainService.saveAnthropic(value)
            anthropic.input = value
            anthropic.original = value
            anthropicValidationTask?.cancel()
            anthropicValidationTask = Task { await validateAnthropic(value) }
        case .tmdb:
            let value = tmdb.input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != tmdb.original else { return }
            KeychainService.saveTMDB(value)
            tmdb.input = value
            tmdb.original = value
            tmdbValidationTask?.cancel()
            tmdbValidationTask = Task { await validateTMDB(value) }
        case .googleBooks:
            let value = googleBooks.input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != googleBooks.original else { return }
            KeychainService.saveGoogleBooks(value)
            googleBooks.input = value
            googleBooks.original = value
            googleBooks.validation = .valid
        }
    }

    private func validateTMDB(_ value: String) async {
        tmdb.validation = .validating
        do {
            let valid = try await TMDBService.validateKey(value)
            guard !Task.isCancelled, tmdb.original == value,
                  KeychainService.loadTMDB() == value else { return }
            tmdb.validation = valid ? .valid : .invalid("Key rejected by TMDB")
        } catch {
            guard !Task.isCancelled, tmdb.original == value,
                  KeychainService.loadTMDB() == value else { return }
            tmdb.validation = .invalid(error.localizedDescription)
        }
    }

    private func validateAnthropic(_ value: String) async {
        anthropic.validation = .validating
        do {
            _ = try await ClaudeService.sendWithSystem(
                "You are a test assistant.",
                user: "Reply with exactly: OK",
                options: .connectionValidation
            )
            guard !Task.isCancelled, anthropic.original == value,
                  KeychainService.loadAnthropic() == value else { return }
            anthropic.validation = .valid
        } catch {
            guard !Task.isCancelled, anthropic.original == value,
                  KeychainService.loadAnthropic() == value else { return }
            anthropic.validation = .invalid(error.localizedDescription)
        }
    }

    private func remove(_ service: ConnectionService) {
        switch service {
        case .anthropic:
            anthropicValidationTask?.cancel()
            anthropicValidationTask = nil
            KeychainService.deleteAnthropic()
            anthropic = KeyEntryState()
        case .tmdb:
            tmdbValidationTask?.cancel()
            tmdbValidationTask = nil
            KeychainService.deleteTMDB()
            tmdb = KeyEntryState()
        case .googleBooks:
            KeychainService.deleteGoogleBooks()
            googleBooks = KeyEntryState()
        }
        pendingRemoval = nil
    }

    private func cancelValidationTasks() {
        anthropicValidationTask?.cancel()
        tmdbValidationTask?.cancel()
        anthropicValidationTask = nil
        tmdbValidationTask = nil
    }
}

private struct KeyEntryState {
    var input = ""
    var original = ""
    var revealed = false
    var validation: KeyValidationState = .idle

    init(stored: String? = nil) {
        let value = stored ?? ""
        input = value
        original = value
    }
}

private enum ConnectionService {
    case anthropic
    case tmdb
    case googleBooks

    var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .tmdb: "TMDB"
        case .googleBooks: "Google Books"
        }
    }

    var purpose: String {
        switch self {
        case .anthropic: "Taste profiles and recommendations"
        case .tmdb: "Movie and TV search, plus Quick Setup"
        case .googleBooks: "Optional import and cover fallback"
        }
    }

    var symbol: String {
        switch self {
        case .anthropic: "wand.and.stars"
        case .tmdb: "film.stack"
        case .googleBooks: "book.closed"
        }
    }

    var placeholder: String { "Paste \(title) API key" }

    var removalConsequence: String {
        switch self {
        case .anthropic: "Taste profile and recommendation generation will stop until another Anthropic key is saved."
        case .tmdb: "Movie and TV search and Quick Setup will stop until another TMDB key is saved."
        case .googleBooks: "Optional Google Books import and cover fallback will use unauthenticated limits."
        }
    }
}

enum KeyValidationState {
    case idle
    case validating
    case valid
    case invalid(String)
}
