import SwiftUI
import SwiftData

struct DashboardScreen: View {
    @EnvironmentObject var store: AppStore
    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false }, sort: \TaskItem.order) private var tasks: [TaskItem]
    @Query(filter: #Predicate<Completion> { $0.isDeleted == false }) private var completions: [Completion]
    let onPickDay: (String) -> Void

    private var stats: Stats {
        let daily = tasks.filter { !$0.isOneOff }
        let ids = Set(daily.map(\.uid))
        var done: [String: Int] = [:]
        for c in completions where ids.contains(c.taskUid) { done[c.day, default: 0] += 1 }
        return computeStats(created: daily.map(\.createdAt), doneByDay: done, today: store.today)
    }

    var body: some View {
        let s = stats
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    StatBlock(label: "Current streak", value: "\(s.streak) day\(s.streak == 1 ? "" : "s")")
                    StatBlock(label: "Perfect days", value: "\(s.perfect)")
                    StatBlock(label: "Days tracked", value: "\(s.tracked)")
                }
                Panel {
                    Text("Daily consistency").font(.themeTitleMedium).foregroundStyle(Theme.ink)
                    Spacer().frame(height: 12)
                    Heatmap(days: s.days, today: s.today, selected: store.selectedDay, onPick: onPickDay)
                    HeatLegend()
                }
                Panel {
                    Text("Average day").font(.themeTitleMedium).foregroundStyle(Theme.ink)
                    Spacer().frame(height: 12)
                    HStack(spacing: 18) {
                        Donut(avgDone: s.avgDone, hasData: s.hasData).frame(width: 120, height: 120)
                        VStack(alignment: .leading, spacing: 10) {
                            StatBlock(label: "done", value: s.hasData ? "\(trim1(s.avgDone))%" : "–")
                            StatBlock(label: "not done", value: s.hasData ? "\(trim1(100 - s.avgDone))%" : "–")
                        }
                    }
                    Text("Average of your daily completion across every day with at least one task.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 12)
                }
                if let q = store.quote {   // hidden entirely when offline
                    VStack(alignment: .leading, spacing: 6) {
                        Text("“\(q.text)”").font(.system(size: 16, design: .serif)).italic().foregroundStyle(Theme.ink)
                        Text(q.author).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DesktopAddressPanel()
                // Very bottom of the dashboard: light/dark switch.
                Button(store.darkTheme ? "Disable dark theme" : "Enable dark theme") { store.darkTheme.toggle() }
                    .buttonStyle(AccentButtonStyle(filled: false))
            }
            .padding(16)
        }
    }
}

/// iOS cannot always broadcast on the LAN, so the desktop's address can be typed in as a fallback.
private struct DesktopAddressPanel: View {
    @EnvironmentObject var store: AppStore
    @State private var text = ""
    var body: some View {
        Panel {
            Text("Desktop address").font(.themeTitleMedium).foregroundStyle(Theme.ink)
            Text("Leave empty to auto-discover. Otherwise enter the desktop's IP, e.g. 192.168.1.20 (port 54322 is the default).")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.vertical, 6)
            HStack {
                TextField("192.168.1.20", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save") {
                    store.manualHost = text
                    Task { await store.syncNow() }
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear { text = store.manualHost }
    }
}

// MARK: heatmap

private func levelColor(_ d: DayCell) -> Color? {
    if d.future { return nil }
    if d.total == 0 { return Theme.noneCell }
    guard let pct = d.pct else { return Theme.noneCell }
    if pct == 0 { return Theme.missed }
    if pct < 34 { return Theme.l1 }
    if pct < 67 { return Theme.l2 }
    if pct < 100 { return Theme.l3 }
    return Theme.l4
}

/// 26-week, Sunday-first consistency grid (GitHub style). Tap a day to open it.
struct Heatmap: View {
    let days: [DayCell]
    let today: String
    let selected: String
    let onPick: (String) -> Void

    private let cell: CGFloat = 15
    private let gap: CGFloat = 4

    var body: some View {
        let weeks = days.count / 7
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: gap) {
                Text("").font(.system(size: 10)).frame(height: 16)
                ForEach(0..<7, id: \.self) { row in
                    Text(row == 1 ? "Mon" : row == 3 ? "Wed" : row == 5 ? "Fri" : "")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted).frame(height: cell)
                }
            }
            .frame(width: 28, alignment: .leading)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<weeks, id: \.self) { w in
                            VStack(spacing: gap) {
                                monthLabel(week: w)
                                ForEach(0..<7, id: \.self) { r in
                                    cellView(days[w * 7 + r])
                                }
                            }
                            .id(w)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .onAppear { proxy.scrollTo(weeks - 1, anchor: .trailing) }
            }
        }
    }

    @ViewBuilder private func monthLabel(week w: Int) -> some View {
        let first = days[w * 7].day
        let show = w == 0 || Day.month(first) != Day.month(days[(w - 1) * 7].day)
        Text(show ? Day.monthShort(first) : "")
            .font(.system(size: 10)).foregroundStyle(Theme.muted)
            .lineLimit(1).fixedSize()
            .frame(width: cell, height: 16, alignment: .leading)
    }

    @ViewBuilder private func cellView(_ d: DayCell) -> some View {
        if let color = levelColor(d) {
            ZStack {
                if d.total == 0 {
                    RoundedRectangle(cornerRadius: 3).stroke(Theme.line, lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(color)
                }
                if d.day == today {
                    RoundedRectangle(cornerRadius: 3).stroke(Theme.ink, lineWidth: 2).padding(-1)
                }
                if d.day == selected {
                    RoundedRectangle(cornerRadius: 3).stroke(Theme.accent, lineWidth: 2).padding(-2)
                }
            }
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
            .onTapGesture { onPick(d.day) }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }
}

struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            sw(Theme.missed); Text("Missed").font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer().frame(width: 6)
            sw(Theme.l1); sw(Theme.l2); sw(Theme.l3); sw(Theme.l4)
            Text("All done").font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .padding(.top, 12)
    }
    private func sw(_ c: Color) -> some View { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 13, height: 13) }
}

struct Donut: View {
    let avgDone: Double
    let hasData: Bool
    var body: some View {
        ZStack {
            Circle().stroke(Theme.notDone, lineWidth: 17)
            Circle().trim(from: 0, to: CGFloat(min(max(avgDone, 0), 100) / 100))
                .stroke(Theme.accent, lineWidth: 17)
                .rotationEffect(.degrees(-90))
            Text(hasData ? "\(Int(avgDone.rounded()))%" : "–")
                .font(.serif(22)).foregroundStyle(Theme.ink)
        }
        .padding(9)
    }
}
