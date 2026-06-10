import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import UserNotifications

struct GoodreadsImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppNavigationState.self) private var navigationState

    @Query(filter: #Predicate<MediaItem> { $0.statusRaw == "completed" })
    private var completedItems: [MediaItem]

    @State private var showFileImporter = false
    @State private var stage: Stage = .instructions
    @State private var selectedFileName: String?
    @State private var parsedBooks: [GoodreadsBook] = []
    @State private var preview: GoodreadsImportPreview?
    @State private var result: ImportResult?
    @State private var preparationProgress = GoodreadsImportPreparationProgress(processed: 0, total: 1, status: "")
    @State private var importProgress = GoodreadsImportProgress(completed: 0, total: 1, currentTitle: "", coverStatus: "")
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private enum Stage {
        case instructions
        case preparing
        case preview
        case importing
        case complete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch stage {
                case .instructions:
                    instructionsView
                case .preparing:
                    preparingView
                case .preview:
                    previewView
                case .importing:
                    importingView
                case .complete:
                    completeView
                }
            }
            .padding(20)
        }
        .background(KonomiTheme.background)
        .navigationTitle("Import from Goodreads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if stage != .importing {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("Import Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong while importing your Goodreads CSV.")
        }
    }

    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Bring your Goodreads library into Konomi in a few steps.")
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.secondary)

            stepCard(number: 1, text: "On Goodreads website go to\nMy Books → Import/Export → Export Library")
            stepCard(number: 2, text: "Download the CSV file to your iPhone\nor transfer from your computer")
            stepCard(number: 3, text: "Tap Import below and select the file")

            Button {
                showFileImporter = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(KonomiTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let selectedFileName {
                Text("Last selected: \(selectedFileName)")
                    .font(.caption)
                    .foregroundStyle(KonomiTheme.secondary)
            }
        }
    }

    private var preparingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(
                value: Double(preparationProgress.processed),
                total: Double(max(preparationProgress.total, 1))
            )
            .tint(KonomiTheme.primary)

            Text("Preparing import preview")
                .font(.headline)
                .foregroundStyle(KonomiTheme.text)

            Text(preparationProgress.status)
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.secondary)

            Text("Processed \(preparationProgress.processed) of \(preparationProgress.total) books")
                .font(.caption)
                .foregroundStyle(KonomiTheme.secondary)
        }
        .padding(18)
        .cardStyle()
    }

    private var previewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let preview {
                summaryCard(title: "Import Preview", rows: [
                    ("Total books found", "\(preview.totalFound)"),
                    ("Already in library", "\(preview.alreadyInLibrary)"),
                    ("New books to import", "\(preview.newBooks)"),
                    ("Books with covers found", "\(preview.booksWithCovers)"),
                    ("Books without covers", "\(preview.booksWithoutCovers)")
                ])

                summaryCard(title: "Shelf Breakdown", rows: [
                    ("Completed", "\(preview.completedCount)"),
                    ("In Progress", "\(preview.inProgressCount)"),
                    ("Want to Read", "\(preview.wantToReadCount)")
                ])

                if preview.alreadyInLibrary > 0 {
                    Text("Duplicates are skipped by ISBN first, then by title and author.")
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.secondary)
                }

                Button {
                    startImport()
                } label: {
                    Label("Confirm Import", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(KonomiTheme.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button("Cancel") {
                    resetImport()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var importingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(
                value: Double(importProgress.completed),
                total: Double(max(importProgress.total, 1))
            )
            .tint(KonomiTheme.primary)

            Text("Importing book \(importProgress.completed) of \(importProgress.total)")
                .font(.headline)

            if !importProgress.currentTitle.isEmpty {
                Text(importProgress.currentTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(KonomiTheme.text)
            }

            Text(importProgress.coverStatus)
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.secondary)

            Text("Konomi will keep working for a while if you send the app to the background, and it will post a notification when the import finishes.")
                .font(.caption)
                .foregroundStyle(KonomiTheme.secondary)
        }
        .padding(18)
        .cardStyle()
    }

    private var completeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import complete! 🎉")
                .font(.title2.weight(.bold))
                .foregroundStyle(KonomiTheme.text)

            if let result {
                summaryCard(title: "Summary", rows: [
                    ("Books imported", "\(result.imported)"),
                    ("Covers found", "\(result.coversFound)"),
                    ("Skipped (duplicates)", "\(result.skipped)"),
                    ("Failed", "\(result.failed)")
                ])
            }

            Button("View Library") {
                navigationState.selectedTab = .library
                dismiss()
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(KonomiTheme.primary)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if shouldSuggestTasteProfile {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Generate your taste profile now?")
                        .font(.headline)
                    Text("You have enough completed ratings for Konomi to analyze your taste.")
                        .font(.subheadline)
                        .foregroundStyle(KonomiTheme.secondary)
                    Button("Open Taste Profile") {
                        navigationState.selectedTab = .profile
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(18)
                .cardStyle()
            }
        }
    }

    private var shouldSuggestTasteProfile: Bool {
        guard let preview else { return false }
        return completedItems.count >= 5 && preview.importedRatingsCount > 0
    }

    private func stepCard(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(KonomiTheme.primary)
                .clipShape(Circle())

            Text(text)
                .font(.body)
                .foregroundStyle(KonomiTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .cardStyle()
    }

    private func summaryCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                    Spacer()
                    Text(row.1)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            selectedFileName = url.lastPathComponent
            stage = .preparing
            preparationProgress = GoodreadsImportPreparationProgress(processed: 0, total: 1, status: "Reading your Goodreads CSV")

            Task {
                await prepareImport(from: url)
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func prepareImport(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let service = GoodreadsImportService(context: context)

        do {
            let books = try GoodreadsImportService.parseCSV(data: Data(contentsOf: url))
            parsedBooks = books

            let preview = try await service.prepareImport(books) { progress in
                Task { @MainActor in
                    preparationProgress = progress
                }
            }

            await MainActor.run {
                self.preview = preview
                self.stage = .preview
            }
        } catch {
            await MainActor.run {
                resetImport()
                presentError(error.localizedDescription)
            }
        }
    }

    private func startImport() {
        guard let preview else { return }

        stage = .importing
        importProgress = GoodreadsImportProgress(
            completed: 0,
            total: max(preview.totalFound, 1),
            currentTitle: "",
            coverStatus: "Starting import..."
        )

        beginBackgroundTask()

        Task {
            await requestNotificationPermissionIfNeeded()
            let service = GoodreadsImportService(context: context)

            do {
                let result = try await service.importPreparedBooks(preview) { progress in
                    Task { @MainActor in
                        importProgress = progress
                    }
                }

                await MainActor.run {
                    self.result = result
                    self.stage = .complete
                    endBackgroundTask()
                }

                await scheduleCompletionNotification(result: result)
            } catch {
                await MainActor.run {
                    endBackgroundTask()
                    resetImport()
                    presentError(error.localizedDescription)
                }
            }
        }
    }

    private func resetImport() {
        stage = .instructions
        parsedBooks = []
        preview = nil
        result = nil
        preparationProgress = GoodreadsImportPreparationProgress(processed: 0, total: 1, status: "")
        importProgress = GoodreadsImportProgress(completed: 0, total: 1, currentTitle: "", coverStatus: "")
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func beginBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "GoodreadsImport") {
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
    }

    private func scheduleCompletionNotification(result: ImportResult) async {
        let content = UNMutableNotificationContent()
        content.title = "Goodreads import complete"
        content.body = "Imported \(result.imported) books with \(result.coversFound) covers found."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "goodreads-import-complete",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
