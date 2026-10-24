import Foundation

/// UTC ISO timestamps, the format the desktop uses for last-write-wins (`yyyy-MM-dd'T'HH:mm:ss'Z'`).
enum Iso {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()
    static func now() -> String { formatter.string(from: Date()) }
    static let epoch = "1970-01-01T00:00:00Z"
    static func isValid(_ s: String) -> Bool {
        s.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", options: .regularExpression) != nil
    }
}

/// Local calendar days as `YYYY-MM-DD` strings (these sort correctly as plain strings).
enum Day {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func string(_ d: Date) -> String { formatter.string(from: d) }
    static func today() -> String { string(Date()) }
    /// Local noon, so daylight-saving shifts can never move a date to a neighbouring day.
    static func parse(_ s: String) -> Date {
        let d = formatter.date(from: s) ?? Date()
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d
    }
    static func add(_ s: String, _ days: Int) -> String {
        string(Calendar.current.date(byAdding: .day, value: days, to: parse(s)) ?? parse(s))
    }
    static func addMonths(_ s: String, _ months: Int) -> String {
        string(Calendar.current.date(byAdding: .month, value: months, to: parse(s)) ?? parse(s))
    }
    /// Sunday = 0 ... Saturday = 6
    static func sinceSunday(_ s: String) -> Int { Calendar.current.component(.weekday, from: parse(s)) - 1 }
    static func month(_ s: String) -> Int { Calendar.current.component(.month, from: parse(s)) }
    static func monthShort(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: parse(s))
    }
    static func full(_ s: String) -> String {
        let f = DateFormatter(); f.dateStyle = .full; return f.string(from: parse(s))
    }
    static func weekday(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: parse(s))
    }
    static func isFuture(_ s: String) -> Bool { s > today() }
}

func trim1(_ v: Double) -> String {
    let r = (v * 10).rounded() / 10
    return r == r.rounded() ? String(Int(r)) : String(r)
}
func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

let kgPerLb = 0.45359237

func formatDuration(_ ms: Int64) -> String {
    let s = Int(ms / 1000)
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}
func formatKm(_ m: Double) -> String { String(format: "%.2f km", m / 1000.0) }
func formatPace(_ secPerKm: Double?) -> String {
    guard let p = secPerKm, !p.isNaN, p <= 3600 else { return "–" }
    let t = Int(p)
    return String(format: "%d:%02d /km", t / 60, t % 60)
}
