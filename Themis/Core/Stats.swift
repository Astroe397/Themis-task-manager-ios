import Foundation

struct DayCell: Identifiable {
    let day: String
    let total: Int
    let done: Int
    let pct: Int?
    let future: Bool
    var id: String { day }
}

struct Stats {
    let days: [DayCell]
    let today: String
    let avgDone: Double
    let tracked: Int
    let perfect: Int
    let streak: Int
    let hasData: Bool
}

/// Port of the desktop `get_stats`: Sunday-first week columns ending this week.
func computeStats(created: [String], doneByDay: [String: Int], today: String, weeks: Int = 26) -> Stats {
    func totals(_ d: String) -> Int { created.filter { $0 <= d }.count }
    let sinceSunday = Day.sinceSunday(today)
    let start = Day.add(today, -(sinceSunday + 7 * (weeks - 1)))
    var days: [DayCell] = []
    for i in 0..<(7 * weeks) {
        let d = Day.add(start, i)
        let future = d > today
        let total = future ? 0 : totals(d)
        let done = future ? 0 : min(doneByDay[d] ?? 0, total)
        let pct: Int? = total > 0 ? Int((100.0 * Double(done) / Double(total)).rounded()) : nil
        days.append(DayCell(day: d, total: total, done: done, pct: pct, future: future))
    }

    var pcts: [Double] = []
    var perfect = 0
    if let first = created.min() {
        var d = first
        while d <= today {
            let t = totals(d)
            if t > 0 {
                let done = min(doneByDay[d] ?? 0, t)
                pcts.append(Double(done) / Double(t))
                if done == t { perfect += 1 }
            }
            d = Day.add(d, 1)
        }
    }
    let avg = pcts.isEmpty ? 0.0 : ((pcts.reduce(0, +) / Double(pcts.count)) * 1000.0).rounded() / 10.0

    // Streak of fully completed days; today doesn't break it while still in progress.
    var streak = 0
    if !created.isEmpty {
        var d = today
        let tt = totals(today)
        if !(tt > 0 && (doneByDay[today] ?? 0) >= tt) { d = Day.add(today, -1) }
        while true {
            let t = totals(d)
            if t > 0 && (doneByDay[d] ?? 0) >= t { streak += 1; d = Day.add(d, -1) } else { break }
        }
    }
    return Stats(days: days, today: today, avgDone: avg, tracked: pcts.count, perfect: perfect,
                 streak: streak, hasData: !pcts.isEmpty)
}

struct WeightPoint: Identifiable {
    let day: String
    let value: Double
    var id: String { day }
}

struct WeightData {
    let unit: String
    let start: String
    let end: String
    let points: [WeightPoint]
    let latest: WeightPoint?
    let change: Double?
    let lowest: Double?
    let highest: Double?
}

func buildWeightData(all: [WeightEntry], unit: String, today: String) -> WeightData {
    let start = Day.addMonths(today, -6)
    func out(_ kg: Double) -> Double { round1(unit == "lb" ? kg / kgPerLb : kg) }
    let mapped = all.filter { !$0.isDeleted }.map { WeightPoint(day: $0.day, value: out($0.kg)) }.sorted { $0.day < $1.day }
    let pts = mapped.filter { $0.day >= start && $0.day <= today }
    return WeightData(
        unit: unit, start: start, end: today, points: pts, latest: mapped.last,
        change: pts.count > 1 ? round1(pts.last!.value - pts.first!.value) : nil,
        lowest: pts.map(\.value).min(), highest: pts.map(\.value).max()
    )
}

/// Chart y-axis bounds: pad 12%, expand tiny ranges, snap to whole numbers.
func axisBounds(_ points: [WeightPoint]) -> (Double, Double) {
    var lo = points.map(\.value).min() ?? 0
    var hi = points.map(\.value).max() ?? 1
    if hi - lo < 2 { lo -= 1; hi += 1 }
    let pad = (hi - lo) * 0.12
    return ((lo - pad).rounded(.down), (hi + pad).rounded(.up))
}
