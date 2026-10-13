import Foundation

struct PlayActivity: Equatable {
    struct Day: Equatable, Identifiable {
        let start: Date
        let duration: TimeInterval
        var id: Date { start }
    }

    struct Title: Equatable, Identifiable {
        let title: String
        let duration: TimeInterval
        var id: String { title }
    }

    let days: [Day]
    let titles: [Title]
    let sessions: Int

    var total: TimeInterval { days.reduce(0) { $0 + $1.duration } }

    init(entries: [LibraryEntry], now: Date = Date(), days count: Int = 7, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let starts = (0..<max(count, 1)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let earliest = starts.first ?? today
        var perDay: [Date: TimeInterval] = [:]
        var perTitle: [String: TimeInterval] = [:]
        var sessions = 0
        for entry in entries {
            for session in entry.sessions ?? [] where session.start >= earliest && session.start <= now {
                let day = calendar.startOfDay(for: session.start)
                perDay[day, default: 0] += session.duration
                perTitle[entry.title, default: 0] += session.duration
                sessions += 1
            }
        }
        self.days = starts.map { Day(start: $0, duration: perDay[$0] ?? 0) }
        self.titles = perTitle.map { Title(title: $0.key, duration: $0.value) }
            .sorted { $0.duration != $1.duration ? $0.duration > $1.duration : $0.title < $1.title }
        self.sessions = sessions
    }

    static func format(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 1 { return duration > 0 ? "<1m" : "0m" }
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }
}
