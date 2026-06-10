import Foundation

enum Formatters {
    static func score(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)"
    }

    static func publicScore(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    static func scoreGapDescription(personal: Int, public publicScore: Double) -> String {
        let gap = Double(personal) - publicScore
        if gap > 1.5 {
            return "You're a fan — you rated this \(String(format: "%.1f", gap)) above the crowd"
        } else if gap < -1.5 {
            return "The crowd liked this more than you did"
        } else {
            return "Your taste aligned with the crowd here"
        }
    }

    static func runtime(_ minutes: Int?) -> String {
        guard let minutes else { return "" }
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    static func serendipityLabel(_ score: Double) -> String {
        switch score {
        case 0..<0.35: return "Safe Pick"
        case 0.35..<0.65: return "Curated Surprise"
        default: return "Wild Card"
        }
    }
}
