import SwiftUI
import SwiftData

struct TasteProfileView: View {
    @Environment(TasteAnalysisService.self) private var tasteService
    @Environment(\.modelContext) private var context

    @Query(sort: \TasteProfile.lastUpdated, order: .reverse)
    private var profiles: [TasteProfile]

    @Query(filter: #Predicate<MediaItem> { $0.statusRaw == "completed" })
    private var completedItems: [MediaItem]

    @State private var errorMessage: String?
    @State private var showError = false

    private var profile: TasteProfile? { profiles.first }
    private var canGenerate: Bool { completedItems.count >= 5 }

    var body: some View {
        ScrollView {
            if let p = profile {
                profileContent(p)
            } else {
                emptyState
            }
        }
        .background(KonomiTheme.background)
        .navigationTitle("Your Taste")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await generateProfile() }
                } label: {
                    if tasteService.isGenerating {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(tasteService.isGenerating || !canGenerate)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
    }

    // MARK: - Profile content

    private func profileContent(_ p: TasteProfile) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Claude's taste description
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(KonomiTheme.primary)
                    Text("Your Taste Profile")
                        .font(.headline)
                        .foregroundStyle(KonomiTheme.text)
                    Spacer()
                    Text(p.formattedDate)
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.secondary)
                }
                Text(p.tasteDescription)
                    .font(.body)
                    .foregroundStyle(KonomiTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .padding(16)
            .cardStyle()

            // Favourite genres
            if !p.favoriteGenres.isEmpty {
                sectionCard(title: "Top Genres") {
                    genreBarChart(genres: Array(p.favoriteGenres.prefix(6)))
                }
            }

            // Strong patterns
            if !p.strongPatterns.isEmpty {
                sectionCard(title: "Your Patterns") {
                    FlowLayout(spacing: 8) {
                        ForEach(p.strongPatterns, id: \.self) { pattern in
                            Text(pattern)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(KonomiTheme.primary.opacity(0.12))
                                .foregroundStyle(KonomiTheme.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Favourite themes
            if !p.favoriteThemes.isEmpty {
                sectionCard(title: "Themes You Love") {
                    FlowLayout(spacing: 8) {
                        ForEach(p.favoriteThemes, id: \.self) { theme in
                            Text(theme)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(KonomiTheme.serendipity.opacity(0.1))
                                .foregroundStyle(KonomiTheme.serendipity)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Favourite creators
            if !p.favoriteCreators.isEmpty {
                sectionCard(title: "Creators You Follow") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(p.favoriteCreators.prefix(8), id: \.self) { creator in
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundStyle(KonomiTheme.secondary.opacity(0.5))
                                Text(creator)
                                    .font(.subheadline)
                                    .foregroundStyle(KonomiTheme.text)
                            }
                        }
                    }
                }
            }

            // Avoid patterns
            if !p.avoidPatterns.isEmpty {
                sectionCard(title: "What You Tend to Dislike") {
                    FlowLayout(spacing: 8) {
                        ForEach(p.avoidPatterns, id: \.self) { pattern in
                            Text(pattern)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(KonomiTheme.secondary.opacity(0.1))
                                .foregroundStyle(KonomiTheme.secondary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 32)
        }
        .padding(16)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 56))
                .foregroundStyle(KonomiTheme.secondary.opacity(0.5))
            Text("Build Your Taste Profile")
                .font(.title3.weight(.semibold))
            Text("Rate \(max(0, 5 - completedItems.count)) more completed items to generate your taste profile")
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if canGenerate {
                Button {
                    Task { await generateProfile() }
                } label: {
                    Label("Generate Profile", systemImage: "sparkles")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(KonomiTheme.primary)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Genre bar chart (manual GeometryReader bars)

    private func genreBarChart(genres: [String]) -> some View {
        let maxCount = genres.count
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(genres.enumerated()), id: \.offset) { idx, genre in
                HStack(spacing: 8) {
                    Text(genre)
                        .font(.subheadline)
                        .foregroundStyle(KonomiTheme.text)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { geo in
                        let width = geo.size.width * CGFloat(maxCount - idx) / CGFloat(maxCount)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(KonomiTheme.primary.opacity(0.8 - Double(idx) * 0.1))
                            .frame(width: max(20, width), height: 20)
                    }
                    .frame(height: 20)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(KonomiTheme.text)
            content()
        }
        .padding(16)
        .cardStyle()
    }

    @MainActor
    private func generateProfile() async {
        do {
            let p = try await tasteService.generateTasteProfile(items: Array(completedItems))
            context.insert(p)
            try? context.save()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
