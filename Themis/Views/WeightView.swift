import SwiftUI
import SwiftData
import Charts

struct WeightScreen: View {
    @EnvironmentObject var store: AppStore
    @Query(filter: #Predicate<WeightEntry> { $0.isDeleted == false }, sort: \WeightEntry.day) private var entries: [WeightEntry]
    @Query private var settings: [SettingEntry]

    @State private var date = Day.today()
    @State private var text = ""
    @State private var error: String?
    @State private var picking = false

    private var unit: String { settings.first(where: { $0.key == "unit" })?.value == "lb" ? "lb" : "kg" }

    var body: some View {
        let w = buildWeightData(all: entries, unit: unit, today: store.today)
        let existing = w.points.first(where: { $0.day == date })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Weight · past 6 months").font(.themeTitleLarge).foregroundStyle(Theme.ink)
                HStack {
                    StatBlock(label: "Latest", value: f(w.latest?.value, w.unit))
                    StatBlock(label: "6-month change", value: w.change.map { (($0 > 0) ? "+" : "") + "\(trim1($0)) \(w.unit)" } ?? "–")
                }
                HStack {
                    StatBlock(label: "Lowest", value: f(w.lowest, w.unit))
                    StatBlock(label: "Highest", value: f(w.highest, w.unit))
                }
                Panel { WeightChart(data: w) }
                Panel {
                    Button { picking = true } label: {
                        Label(Day.full(date), systemImage: "calendar")
                    }
                    .buttonStyle(AccentButtonStyle(filled: false))
                    HStack(spacing: 8) {
                        TextField("Weight", text: $text)
                            .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                        ForEach(["kg", "lb"], id: \.self) { u in
                            Button(u) { store.setUnit(u) }
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(w.unit == u ? Theme.ink : Theme.muted)
                                .background(w.unit == u ? Theme.l1 : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.top, 8)
                    if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.errorRed).padding(.top, 6) }
                    HStack {
                        Button("Save weight") {
                            error = store.setWeight(day: date, value: Double(text.replacingOccurrences(of: ",", with: ".")), unit: w.unit)
                        }
                        .buttonStyle(AccentButtonStyle())
                        .frame(maxWidth: 180)
                        if existing != nil {
                            Button("Remove entry") { store.deleteWeight(day: date) }.foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.top, 10)
                    Text("One entry per day. Saving again on the same date replaces it.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 8)
                }
                Divider().overlay(Theme.line)
                StrengthSection()
            }
            .padding(16)
        }
        .onChange(of: date) { _, _ in prefill(existing: nil, w: w) }
        .onChange(of: w.unit) { _, _ in prefill(existing: nil, w: w) }
        .onAppear { prefill(existing: nil, w: w) }
        .sheet(isPresented: $picking) { DatePickerSheet(initial: date) { date = $0 } }
    }

    /// Prefill the field with the day's saved weight, like the desktop.
    private func prefill(existing: WeightPoint?, w: WeightData) {
        if let p = w.points.first(where: { $0.day == date }) { text = trim1(p.value) } else { text = "" }
    }

    private func f(_ v: Double?, _ unit: String) -> String { v.map { "\(trim1($0)) \(unit)" } ?? "–" }
}

struct WeightChart: View {
    let data: WeightData
    var body: some View {
        if data.points.isEmpty {
            Text("No weight logged in the last 6 months yet.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            let (lo, hi) = axisBounds(data.points)
            Chart(data.points) { p in
                LineMark(x: .value("Day", Day.parse(p.day)), y: .value("Weight", p.value))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Day", Day.parse(p.day)), y: .value("Weight", p.value))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(30)
            }
            .chartYScale(domain: lo...hi)
            .chartXScale(domain: Day.parse(data.start)...Day.parse(data.end))
            .chartYAxisLabel(data.unit, position: .top, alignment: .leading)
            .frame(height: 200)
        }
    }
}
