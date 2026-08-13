import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query private var allItems: [MediaItem]
    @Query private var settings: [AppSettings]

    private var completedItems: [MediaItem] { allItems.filter(\.isCompleted) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if completedItems.isEmpty {
                    ContentUnavailableView(
                        "No Insights Yet",
                        systemImage: "chart.bar",
                        description: Text("Complete some items to see how your taste is taking shape.")
                    )
                    .padding(.top, 80)
                } else {
                    summaryStrip

                    if paceData().contains(where: { $0.count > 0 }) {
                        paceChart
                    }

                    if scoreDistribution().contains(where: { $0.count > 0 }) {
                        scoreDistributionChart
                    }

                    if !topGenres().isEmpty {
                        rankedGenres
                    }

                    if settings.first?.showPublicScores ?? true,
                       completedItems.contains(where: { $0.publicScore != nil }) {
                        scoreGapCard
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(KonomiTheme.canvas)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
    }

    private var summaryStrip: some View {
        let average = completedItems.compactMap(\.personalScore).average
            .map { String(format: "%.1f", $0) } ?? "not available"

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                statCell(value: "\(allItems.count)", label: "Total")
                Divider().frame(height: 36)
                statCell(value: "\(completedItems.count)", label: "Completed")
                Divider().frame(height: 36)
                statCell(
                    value: completedItems.compactMap(\.personalScore).average
                        .map { String(format: "%.1f", $0) } ?? "—",
                    label: "Avg Score"
                )
            }
            .accessibilityElement(children: .contain)

            VStack(spacing: 12) {
                statCell(value: "\(allItems.count)", label: "Total")
                Divider()
                statCell(value: "\(completedItems.count)", label: "Completed")
                Divider()
                statCell(
                    value: completedItems.compactMap(\.personalScore).average
                        .map { String(format: "%.1f", $0) } ?? "—",
                    label: "Avg Score"
                )
            }
            .accessibilityElement(children: .contain)
        }
        .accessibilityElement(children: .contain)
        .padding(16)
        .surfaceSection()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Library summary")
        .accessibilityValue("\(allItems.count) total, \(completedItems.count) completed, average score \(average)")
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(KonomiTheme.persimmon)
            Text(label)
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var paceChart: some View {
        let data = paceData()
        let total = data.reduce(0) { $0 + $1.count }

        return chartSection(title: "Completed Per Month") {
            Chart(data) { point in
                BarMark(
                    x: .value("Month", point.label),
                    y: .value("Completed", point.count)
                )
                .foregroundStyle(KonomiTheme.persimmon)
                .cornerRadius(4)
                .accessibilityLabel(point.label)
                .accessibilityValue("\(point.count) completed")
            }
            .frame(height: 170)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(anchor: .top)
                        .font(.caption2)
                }
            }
            .accessibilityElement(children: .contain)

            chartSummary("\(total) items completed across the last 12 months.")
        }
    }

    private var scoreDistributionChart: some View {
        let distribution = scoreDistribution()
        let ratedCount = distribution.reduce(0) { $0 + $1.count }

        return chartSection(title: "Your Score Distribution") {
            Chart(distribution) { point in
                BarMark(
                    x: .value("Score", point.score),
                    y: .value("Ratings", point.count),
                    width: .fixed(16)
                )
                .foregroundStyle(point.score >= 8
                    ? KonomiTheme.persimmon
                    : point.score >= 6
                        ? Color.orange
                        : KonomiTheme.inkSecondary)
                .cornerRadius(4)
                .accessibilityLabel("Score \(point.score)")
                .accessibilityValue("\(point.count) ratings")
            }
            .frame(height: 150)
            .chartXScale(domain: 0.5...10.5)
            .chartXAxis {
                AxisMarks(values: Array(1...10))
            }
            .accessibilityElement(children: .contain)

            chartSummary("\(ratedCount) completed items have a personal score.")
        }
    }

    private var rankedGenres: some View {
        let genres = topGenres()
        let maximum = genres.map(\.count).max() ?? 1

        return chartSection(title: "Top Genres") {
            VStack(spacing: 14) {
                ForEach(Array(genres.enumerated()), id: \.element.id) { index, point in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(KonomiTheme.inkSecondary)
                            .frame(width: 18, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(point.genre)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(KonomiTheme.ink)
                                Spacer()
                                Text("\(point.count)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(KonomiTheme.inkSecondary)
                            }

                            ProgressView(value: Double(point.count), total: Double(maximum))
                                .tint(KonomiTheme.tasteViolet)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rank \(index + 1), \(point.genre)")
                    .accessibilityValue("\(point.count) completed items")
                }
            }

            chartSummary("Ranked by completed items; showing up to six genres.")
        }
    }

    private var scoreGapCard: some View {
        let itemsWithPublic = completedItems.filter { $0.publicScore != nil }
        let personal = itemsWithPublic.compactMap(\.personalScore).average
        let publicAverage = itemsWithPublic.compactMap(\.publicScore).average
        let youHigher = itemsWithPublic.filter { Double($0.personalScore ?? 0) > ($0.publicScore ?? 0) + 1 }.count
        let youLower = itemsWithPublic.filter { Double($0.personalScore ?? 0) < ($0.publicScore ?? 0) - 1 }.count

        return VStack(alignment: .leading, spacing: 16) {
            Text("You vs. The Crowd")
                .font(.headline)
                .foregroundStyle(KonomiTheme.ink)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 28) {
                    averageCell(value: personal, label: "Your Average", color: KonomiTheme.persimmon)
                    averageCell(value: publicAverage, label: "Public Average", color: KonomiTheme.inkSecondary)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 12) {
                    averageCell(value: personal, label: "Your Average", color: KonomiTheme.persimmon)
                    averageCell(value: publicAverage, label: "Public Average", color: KonomiTheme.inkSecondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    comparisonLabel(count: youHigher, direction: "rated higher", systemImage: "arrow.up", color: KonomiTheme.success)
                    comparisonLabel(count: youLower, direction: "rated lower", systemImage: "arrow.down", color: .red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    comparisonLabel(count: youHigher, direction: "rated higher", systemImage: "arrow.up", color: KonomiTheme.success)
                    comparisonLabel(count: youLower, direction: "rated lower", systemImage: "arrow.down", color: .red)
                }
            }
        }
        .padding(16)
        .surfaceSection()
    }

    private func averageCell(value: Double?, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { String(format: "%.1f", $0) } ?? "—")
                .font(.title.bold())
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(KonomiTheme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func comparisonLabel(count: Int, direction: String, systemImage: String, color: Color) -> some View {
        Label("\(count) \(direction)", systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func paceData() -> [PacePoint] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<12).reversed().compactMap { monthsBack in
            guard let date = calendar.date(byAdding: .month, value: -monthsBack, to: now) else {
                return nil
            }
            let count = completedItems.filter { item in
                guard let completed = item.dateCompleted else { return false }
                return calendar.isDate(completed, equalTo: date, toGranularity: .month)
            }.count
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return PacePoint(label: formatter.string(from: date), count: count)
        }
    }

    private func scoreDistribution() -> [ScorePoint] {
        (1...10).map { score in
            ScorePoint(
                score: score,
                count: completedItems.filter { $0.personalScore == score }.count
            )
        }
    }

    private func topGenres() -> [GenrePoint] {
        var counts: [String: Int] = [:]
        for item in completedItems {
            for genre in item.genres where !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }
        return counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending : lhs.value > rhs.value
            }
            .prefix(6)
            .map { GenrePoint(genre: $0.key, count: $0.value) }
    }

    private func chartSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(KonomiTheme.ink)
            content()
        }
        .padding(16)
        .surfaceSection()
    }

    private func chartSummary(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(KonomiTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    func surfaceSection() -> some View {
        background(KonomiTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius))
            .overlay {
                RoundedRectangle(cornerRadius: KonomiTheme.sectionRadius)
                    .stroke(KonomiTheme.hairline, lineWidth: 1)
            }
    }
}

struct PacePoint: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
}

struct ScorePoint: Identifiable {
    var id: Int { score }
    let score: Int
    let count: Int
}

struct GenrePoint: Identifiable {
    var id: String { genre }
    let genre: String
    let count: Int
}

extension Array where Element == Int {
    var average: Double? {
        guard !isEmpty else { return nil }
        return Double(reduce(0, +)) / Double(count)
    }
}

extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
