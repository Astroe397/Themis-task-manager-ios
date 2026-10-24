import SwiftUI
import SwiftData

func kgOut(_ kg: Double, _ unit: String) -> Double { unit == "lb" ? kg / kgPerLb : kg }
func wText(_ kg: Double, _ unit: String) -> String { "\(Int(kgOut(kg, unit).rounded())) \(unit)" }

// MARK: badge

/// Shield emblem in the tier's colour with a soft glow; the tier number sits inside.
struct ShieldShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + w * x, y: r.minY + h * y) }
        var p = Path()
        p.move(to: pt(0.5, 0.06))
        p.addLine(to: pt(0.88, 0.2))
        p.addLine(to: pt(0.88, 0.52))
        p.addCurve(to: pt(0.5, 0.96), control1: pt(0.88, 0.76), control2: pt(0.66, 0.9))
        p.addCurve(to: pt(0.12, 0.52), control1: pt(0.34, 0.9), control2: pt(0.12, 0.76))
        p.addLine(to: pt(0.12, 0.2))
        p.closeSubpath()
        return p
    }
}

struct RankBadge: View {
    let tier: RankTier?
    var size: CGFloat = 56
    var glow = true
    var showLevel = true

    var body: some View {
        let col = tier?.color ?? Theme.muted
        ZStack {
            if glow, tier != nil {
                Circle().fill(RadialGradient(colors: [col.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: size * 0.62))
                    .frame(width: size * 1.24, height: size * 1.24)
            }
            ShieldShape().fill(LinearGradient(colors: [col, col.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            ShieldShape().stroke(Color.white.opacity(tier == nil ? 0.15 : 0.55), lineWidth: size * 0.04)
            ShieldShape().fill(Color.black.opacity(0.18)).scaleEffect(0.62)
            if let n = tier?.level {
                HStack(spacing: size * 0.045) {
                    ForEach(0..<n, id: \.self) { _ in Circle().fill(Color.white.opacity(0.9)).frame(width: size * 0.04, height: size * 0.04) }
                }
                .offset(y: size * 0.24)
            }
            if showLevel {
                Text(tier.map { String($0.level) } ?? "–")
                    .font(.system(size: size * 0.34, weight: .black)).foregroundStyle(.white)
                    .offset(y: -size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(tier.map { "\($0.label) rank" } ?? "Unranked")
    }
}

// MARK: ladder

/// Vertical ladder, Olympian at the top. `multiplier` scales the thresholds to the group's best lift (1 = bench-press scale).
struct TierLadderView: View {
    let current: Standing?
    let multiplier: Double
    let unit: String
    let liftName: String?

    var body: some View {
        Panel {
            Text("Tier ladder").font(.themeTitleMedium).foregroundStyle(Theme.ink)
            Text(liftName.map { "Thresholds for \($0) (estimated 1RM)" } ?? "Bench-press scale (estimated 1RM)")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.bottom, 10)
            let tiers = Array(RankTier.allCases.reversed())
            ForEach(Array(tiers.enumerated()), id: \.element.id) { i, t in
                let reached = current.map { $0.tier.rawValue >= t.rawValue } ?? false
                let isCurrent = current?.tier == t
                HStack(spacing: 0) {
                    ZStack {
                        Rectangle().fill(reached ? t.color : Theme.line).frame(width: 3)
                            .padding(.top, i == 0 ? 20 : 0).padding(.bottom, i == tiers.count - 1 ? 20 : 0)
                        Circle().fill(reached ? t.color : Theme.surface).frame(width: isCurrent ? 16 : 10, height: isCurrent ? 16 : 10)
                        Circle().stroke(reached ? t.color : Theme.line, lineWidth: 2).frame(width: isCurrent ? 16 : 10, height: isCurrent ? 16 : 10)
                    }
                    .frame(width: 28, height: 46)
                    HStack(spacing: 10) {
                        RankBadge(tier: reached ? t : nil, size: 26, glow: false, showLevel: false)
                        Text(t.label).fontWeight(isCurrent ? .bold : .regular).foregroundStyle(reached ? Theme.ink : Theme.muted)
                        Spacer()
                        Text(t.rawValue == 0 ? "start" : wText(t.baseKg * multiplier, unit))
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(isCurrent ? t.color.opacity(0.16) : Color.clear)
                    .padding(.vertical, 3)
                }
                .frame(height: 46)
            }
        }
    }
}

// MARK: group cards

private struct GroupCard: View {
    let rank: GroupRank
    let unit: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let st = rank.standing
        let col = st?.tier.color ?? Theme.line
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RankBadge(tier: st?.tier, size: 46)
                VStack(alignment: .leading) {
                    Text(rank.group.label).fontWeight(.semibold).foregroundStyle(Theme.ink)
                    Text(st?.tier.label ?? "Unranked").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(st?.tier.color ?? Theme.muted)
                }
            }
            Text(rank.best.map { "1RM \(wText($0.e1rmKg, unit)) · \($0.exerciseName)" } ?? "No lifts in the last 30 days")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
            ProgressView(value: st?.progress ?? 0).tint(col)
            Text({ () -> String in
                guard let st else { return "Log a lift to get ranked" }
                guard let next = st.tier.next else { return "Top tier reached" }
                return "\(Int(st.progress * 100))% to \(next.label)"
            }())
            .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface)
        .background(selected ? col.opacity(0.10) : Color.clear)
        .overlay(Rectangle().stroke(selected ? col : Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: section

/// The whole Muscle Strength & Workout Logging block, placed under the weight tracker.
struct StrengthSection: View {
    @EnvironmentObject var store: AppStore
    @Query(sort: \Exercise.order) private var exercises: [Exercise]
    @Query(filter: #Predicate<SetLog> { $0.isDeleted == false }, sort: \SetLog.timestamp, order: .reverse) private var allSets: [SetLog]
    @Query private var settings: [SettingEntry]
    @State private var logging = false

    private var unit: String { settings.first(where: { $0.key == "unit" })?.value == "lb" ? "lb" : "kg" }

    var body: some View {
        let since = AppStore.windowStartMs()
        let ranks = StrengthEngine.groupRanks(exercises: exercises, sets: allSets.filter { $0.timestamp >= since })
        let sel = ranks.first { $0.group == store.selectedGroup }
        let mult = sel?.best.map { $0.e1rmKg / $0.normalizedKg } ?? 1.0
        let anyRanked = ranks.contains { $0.standing != nil }
        let recent = allSets.sorted { ($0.timestamp, $0.uid) > ($1.timestamp, $1.uid) }.prefix(8)

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Muscle strength").font(.themeTitleLarge).foregroundStyle(Theme.ink)
                Spacer()
                Button { store.sharingRanks = true } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18))
                        .foregroundStyle(anyRanked ? Theme.accent : Theme.muted.opacity(0.45))
                }
                .disabled(!anyRanked)
                .accessibilityLabel("Share muscle ranks")
            }
            Text("Ranks use your best estimated 1RM per muscle group over the last 30 days.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            ForEach(Array(stride(from: 0, to: ranks.count, by: 2)), id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(ranks[i..<min(i + 2, ranks.count)]) { r in
                        GroupCard(rank: r, unit: unit, selected: r.group == store.selectedGroup) { store.selectedGroup = r.group }
                    }
                }
            }
            Button { logging = true } label: { Label("Log exercise", systemImage: "plus") }
                .buttonStyle(AccentButtonStyle())
            Button { store.sharingRanks = true } label: { Label("Share ranks", systemImage: "square.and.arrow.up") }
                .buttonStyle(AccentButtonStyle(filled: false))
                .disabled(!anyRanked)
            Text("\(sel?.group.label ?? "") ladder").font(.system(size: 12)).foregroundStyle(Theme.muted)
            TierLadderView(current: sel?.standing, multiplier: mult, unit: unit, liftName: sel?.best?.exerciseName)
            if !recent.isEmpty {
                Panel {
                    Text("Recent sets").font(.themeTitleMedium).foregroundStyle(Theme.ink)
                    ForEach(Array(recent), id: \.uid) { s in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s.exerciseName).fontWeight(.semibold).foregroundStyle(Theme.ink)
                                Text("\(wText(s.weightKg, unit)) × \(s.reps) · 1RM \(wText(s.estimatedOneRepMax, unit)) · \(shortDay(s.timestamp))")
                                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button { store.deleteSet(uid: s.uid) } label: {
                                Image(systemName: "trash").foregroundStyle(Theme.muted).frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("Delete set")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .sheet(isPresented: $logging) { LogExerciseSheet(unit: unit, ranks: ranks, onLogged: { logging = false }) }
        .sheet(item: $store.lastResult) { r in PromotionView(result: r, unit: unit) { store.lastResult = nil } }
    }

    private func shortDay(_ ms: Int64) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}

// MARK: log sheet

struct LogExerciseSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.order) private var exercises: [Exercise]
    let unit: String
    let ranks: [GroupRank]
    let onLogged: () -> Void

    @State private var group: MuscleGroup = .chest
    @State private var exName: String?
    @State private var sets = 3
    @State private var reps = 8
    @State private var weight = ""
    @State private var error: String?

    var body: some View {
        let inGroup = exercises.filter { $0.primaryMuscleGroup == group.rawValue }
        let ex = inGroup.first(where: { $0.name == exName }) ?? inGroup.first
        let bw = store.latestBodyweightKg()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MuscleGroup.allCases) { g in
                                chip(g.label, group == g) { group = g; exName = nil }
                            }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(inGroup, id: \.name) { e in chip(e.name, e.name == ex?.name) { exName = e.name } }
                        }
                    }
                    if ex?.usesBodyweight == true {
                        Text(bw != nil ? "Body weight (\(wText(bw!, unit))) counts towards the load. Enter extra weight, or 0."
                                       : "Log your body weight above first so pull-ups can be ranked.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    stepper("Sets", $sets, 1, 20)
                    stepper("Reps", $reps, 1, 30)
                    TextField(ex?.usesBodyweight == true ? "Added weight (\(unit))" : "Weight per rep (\(unit))", text: $weight)
                        .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                    preview(ex: ex, bw: bw)
                    if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.errorRed) }
                    Button("Log \(sets) × \(reps)") {
                        error = nil
                        guard let e = ex else { return }
                        let parsed = Double(weight.replacingOccurrences(of: ",", with: "."))
                        let w = (e.usesBodyweight && weight.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.0 : parsed
                        if let msg = store.logSets(exercise: e, sets: sets, reps: reps, weightInUnit: w) { error = msg } else { onLogged() }
                    }
                    .buttonStyle(AccentButtonStyle())
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Log exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear { group = store.selectedGroup }
        .presentationDetents([.large])
    }

    @ViewBuilder private func preview(ex: Exercise?, bw: Double?) -> some View {
        if let ex, let w = Double(weight.replacingOccurrences(of: ",", with: ".")), w >= 0 {
            let kg = unit == "lb" ? w * kgPerLb : w
            let eff = kg + (ex.usesBodyweight ? (bw ?? 0) : 0)
            if eff > 0 {
                let e1 = StrengthEngine.epley(weightKg: eff, reps: reps)
                let after = StrengthEngine.standing(normalizedKg: e1 / ex.baselineMultiplier)
                let before = ranks.first(where: { $0.group == group })?.standing
                Panel {
                    HStack(spacing: 12) {
                        RankBadge(tier: after.tier, size: 44)
                        VStack(alignment: .leading) {
                            Text("Estimated 1RM \(wText(e1, unit))").fontWeight(.semibold).foregroundStyle(Theme.ink)
                            Text(previewLine(before: before, after: after))
                                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    private func previewLine(before: Standing?, after: Standing) -> String {
        guard let before else { return "Would start \(group.label) at \(after.tier.label)" }
        if after.tier.rawValue > before.tier.rawValue { return "Would promote \(before.tier.label) → \(after.tier.label)" }
        return "\(group.label) stays \(before.tier.label)"
    }

    private func chip(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(on ? Theme.ink : Theme.muted)
                .background(on ? Theme.l1 : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func stepper(_ label: String, _ value: Binding<Int>, _ lo: Int, _ hi: Int) -> some View {
        HStack {
            Text(label).font(.themeTitleMedium).foregroundStyle(Theme.ink)
            Spacer()
            Button { value.wrappedValue = max(value.wrappedValue - 1, lo) } label: {
                Text("\u{2212}").font(.system(size: 22, weight: .bold)).frame(width: 44, height: 44)
                    .background(Theme.l1.opacity(0.6)).clipShape(Circle())
            }
            .accessibilityLabel("Fewer \(label)")
            Text("\(value.wrappedValue)").font(.system(size: 20, weight: .bold)).frame(width: 48)
            Button { value.wrappedValue = min(value.wrappedValue + 1, hi) } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
                    .background(Theme.l1.opacity(0.6)).clipShape(Circle())
            }
            .accessibilityLabel("More \(label)")
        }
        .foregroundStyle(Theme.ink)
    }
}

// MARK: promotion

struct PromotionView: View {
    let result: LogResult
    let unit: String
    let onClose: () -> Void
    @State private var scale = 0.4

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.themeTitleLarge).multilineTextAlignment(.center).foregroundStyle(Theme.ink)
            RankBadge(tier: result.after.tier, size: 96).scaleEffect(scale)
            Text("\(result.sets) × \(result.reps) \(result.exerciseName)").fontWeight(.semibold).foregroundStyle(Theme.ink)
            Text("Estimated 1RM \(wText(result.e1rmKg, unit))").foregroundStyle(Theme.muted)
            Text(result.after.tier.next.map { "\(Int(result.after.progress * 100))% of the way to \($0.label)" } ?? "You're at the top tier.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            Button("Nice", action: onClose).buttonStyle(AccentButtonStyle()).frame(maxWidth: 200).padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .presentationDetents([.medium])
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) { scale = 1 } }
    }

    private var title: String {
        if result.promoted, let b = result.before { return "Promoted from \(b.tier.label) to \(result.after.tier.label)!" }
        if result.before == nil { return "\(result.group.label) ranked \(result.after.tier.label)" }
        if result.newBest { return "New personal best" }
        return "Logged"
    }
}
