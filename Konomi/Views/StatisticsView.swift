import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query private var allItems: [MediaItem]

    private var completedItems: [MediaItem] { allItems.filter(\.isCompleted) }

    var body: some View {
        ScrollView {
                VStack(spacing: 20) {
                    summaryStrip
                        .padding(.horizontal, 16)

                    if completedItems.isEmpty {
                        ContentUnavailableView(
                            "No Data Yet",
                            systemImage: "chart.bar",
                            description: Text("Complete some items to see your statistics")
                        )
                        .frame(height: 300)
                    } else {
                        paceChart
                            .padding(.horizontal, 16)

                        scoreDistributionChart
                            .padding(.horizontal, 16)

                        genreDonutChart
                            .padding(.horizontal, 16)

                        scoreGapCard
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.top, 8)
            }
            .background(KonomiTheme.background)
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Summary strip

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            statCell(value: allItems.count, label: "Total")
            Divider().frame(height: 36)
            statCell(value: completedItems.count, label: "Completed")
            Divider().frame(height: 36)
            let avgScore = completedItems.compactMap(\.personalScore).average
            VStack(spacing: 2) {
                Text(avgScore.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.title2.bold())
                    .foregroundStyle(KonomiTheme.primary)
                Text("Avg Score")
                    .font(.caption)
                    .foregroundStyle(KonomiTheme.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .cardStyle()
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(KonomiTheme.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(KonomiTheme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pace chart (items completed per month, last 12)

    private var paceChart: some View {
        let data = paceData()
        return chartCard(title: "Completed Per Month") {
            Chart(data) { point in
                BarMark(
                    x: .value("Month", point.label),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(KonomiTheme.primary)
                .cornerRadius(4)
            }
            .frame(height: 160)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisValueLabel(anchor: .top)
                        .font(.caption2)
                }
            }
        }
    }

    // MARK: - Score distribution

    private var scoreDistributionChart: some View {
        let dist = scoreDistribution()
        return chartCard(title: "Your Score Distribution") {
            Chart(dist) { point in
                BarMark(
                    x: .value("Score", "\(point.score)"),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(point.score >= 8
                    ? KonomiTheme.primary
                    : point.score >= 6
                        ? Color(hex: "#FF9F0A")
                        : KonomiTheme.secondary)
                .cornerRadius(4)
            }
            .frame(height: 140)
        }
    }

    // MARK: - Genre donut

    private var genreDonutChart: some View {
        let genres = topGenres()
        return chartCard(title: "Top Genres") {
            HStack {
                Chart(genres) { point in
                    SectorMark(
                        angle: .value("Count", point.count),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Genre", point.genre))
                    .cornerRadius(4)
                }
                .chartLegend(position: .trailing, alignment: .center, spacing: 8)
                .frame(height: 180)
            }
        }
    }

    // MARK: - Score gap card

    private var scoreGapCard: some View {
        let personal = completedItems.compactMap(\.personalScore).average ?? 0
        let itemsWithPublic = completedItems.filter { $0.publicScore != nil }
        let publicAvg = itemsWithPublic.compactMap(\.publicScore).average ?? 0
        let youHigher = itemsWithPublic.filter { Double($0.personalScore ?? 0) > ($0.publicScore ?? 0) + 1 }.count
        let youLower = itemsWithPublic.filter { Double($0.personalScore ?? 0) < ($0.publicScore ?? 0) - 1 }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("You vs. The Crowd")
                .font(.headline)
                .foregroundStyle(KonomiTheme.text)

            HStack(spacing: 20) {
                VStack {
                    Text(String(format: "%.1f", personal))
                        .font(.title.bold())
                        .foregroundStyle(KonomiTheme.primary)
                    Text("Your Average")
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.secondary)
                }
                if publicAvg > 0 {
                    VStack {
                        Text(String(format: "%.1f", publicAvg))
                            .font(.title.bold())
                            .foregroundStyle(KonomiTheme.secondary)
                        Text("Public Average")
                            .font(.caption)
                            .foregroundStyle(KonomiTheme.secondary)
                    }
                }
                Spacer()
            }

            if !itemsWithPublic.isEmpty {
                HStack(spacing: 16) {
                    Label("\(youHigher) rated higher", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(KonomiTheme.success)
                    Label("\(youLower) rated lower", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#FF453A"))
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - Data helpers

    private func paceData() -> [PacePoint] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<12).reversed().map { monthsBack in
            let date = calendar.date(byAdding: .month, value: -monthsBack, to: now)!
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
            let count = completedItems.filter { $0.personalScore == score }.count
            return ScorePoint(score: score, count: count)
        }
    }

    private func topGenres() -> [GenrePoint] {
        var counts: [String: Int] = [:]
        for item in completedItems {
            for genre in item.genres { counts[genre, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }
            .prefix(6)
            .map { GenrePoint(genre: $0.key, count: $0.value) }
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(KonomiTheme.text)
            content()
        }
        .padding(16)
        .cardStyle()
    }
}

// MARK: - Chart data types

struct PacePoint: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}

struct ScorePoint: Identifiable {
    let id = UUID()
    let score: Int
    let count: Int
}

struct GenrePoint: Identifiable {
    let id = UUID()
    let genre: String
    let count: Int
}

// MARK: - Array average helper

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
