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
    private var ratedCompletedCount: Int { completedItems.filter { $0.personalScore != nil }.count }
    private var canGenerate: Bool { ratedCompletedCount >= TasteAnalysisService.minimumRatedItems }

    var body: some View {
        ScrollView {
            if let profile {
                profileContent(profile)
            } else {
                emptyState
            }
        }
        .background(KonomiTheme.canvas)
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
                .accessibilityLabel("Refresh taste profile")
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
    }

    private func profileContent(_ profile: TasteProfile) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            narrative(profile)

            if !profile.favoriteGenres.isEmpty || !profile.strongPatterns.isEmpty || !profile.favoriteThemes.isEmpty {
                profileSection(title: "What draws you in") {
                    if !profile.favoriteGenres.isEmpty {
                        factGroup(title: "Top genres") {
                            chips(Array(profile.favoriteGenres.prefix(6)), color: KonomiTheme.persimmon)
                        }
                    }
                    if !profile.strongPatterns.isEmpty {
                        factGroup(title: "Patterns") {
                            chips(profile.strongPatterns, color: KonomiTheme.persimmon)
                        }
                    }
                    if !profile.favoriteThemes.isEmpty {
                        factGroup(title: "Themes") {
                            chips(profile.favoriteThemes, color: KonomiTheme.tasteViolet)
                        }
                    }
                }
            }

            if !profile.favoriteCreators.isEmpty {
                profileSection(title: "Creators you follow") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(profile.favoriteCreators.prefix(8), id: \.self) { creator in
                            Label(creator, systemImage: "person.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(KonomiTheme.ink)
                        }
                    }
                }
            }

            if !profile.avoidPatterns.isEmpty {
                profileSection(title: "What tends not to work") {
                    chips(profile.avoidPatterns, color: KonomiTheme.inkSecondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 40)
    }

    private func narrative(_ profile: TasteProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                TasteContourView()
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("好み · PERSONAL TASTE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KonomiTheme.persimmon)
                    Text("A portrait of what moves you")
                        .font(.subheadline)
                        .foregroundStyle(KonomiTheme.inkSecondary)
                }
            }

            Text(profile.tasteDescription)
                .font(.body)
                .fontDesign(.serif)
                .foregroundStyle(KonomiTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(5)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    profileMetadata(profile)
                    Spacer(minLength: 8)
                    insightsLink
                }

                VStack(alignment: .leading, spacing: 12) {
                    profileMetadata(profile)
                    insightsLink
                }
            }
        }
    }

    private func profileMetadata(_ profile: TasteProfile) -> some View {
        Text("Based on \(ratedCompletedCount) ratings · Updated \(profile.formattedDate)")
            .font(.caption)
            .foregroundStyle(KonomiTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var insightsLink: some View {
        NavigationLink(value: TasteRoute.insights) {
            Label("Insights", systemImage: "chart.bar.xaxis")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityHint("Opens charts and ranked taste data")
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            TasteContourView(strength: .compact)
                .frame(width: 104, height: 104)
            Text("Build Your Taste Profile")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
            Text(canGenerate
                 ? "Your ratings are ready to become a taste portrait."
                 : "Rate \(max(0, TasteAnalysisService.minimumRatedItems - ratedCompletedCount)) more completed items to generate your taste profile.")
                .font(.subheadline)
                .foregroundStyle(KonomiTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if canGenerate {
                Button {
                    Task { await generateProfile() }
                } label: {
                    Label(tasteService.isGenerating ? "Generating Profile…" : "Generate Profile", systemImage: "sparkles")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(KonomiTheme.persimmon)
                        .foregroundStyle(KonomiTheme.onPersimmon)
                        .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.controlRadius))
                }
                .disabled(tasteService.isGenerating)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func profileSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(KonomiTheme.ink)
            content()
        }
        .padding(16)
        .background(KonomiTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius)
                .stroke(KonomiTheme.hairline, lineWidth: 1)
        }
    }

    private func factGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KonomiTheme.inkSecondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func chips(_ values: [String], color: Color) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.11))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }
        }
    }

    @MainActor
    private func generateProfile() async {
        do {
            let profile = try await tasteService.generateTasteProfile(items: Array(completedItems))
            try GeneratedContentStore.replaceTasteProfile(profile, in: context)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
