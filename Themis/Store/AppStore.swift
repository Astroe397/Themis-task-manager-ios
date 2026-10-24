import Foundation
import SwiftData
import SwiftUI

enum SyncState { case searching, synced, offline }
struct SyncUi { var state: SyncState; var label: String }

/// What a logging action did to the muscle group's rank, for the promotion screen.
struct LogResult: Identifiable {
    let id = UUID()
    let exerciseName: String
    let group: MuscleGroup
    let sets: Int
    let reps: Int
    let e1rmKg: Double
    let before: Standing?
    let after: Standing
    let newBest: Bool
    var promoted: Bool { before != nil && after.tier.rawValue > before!.tier.rawValue }
}

/// Repository + app-wide UI state. Views read their lists with `@Query`; every mutation goes through here.
@MainActor
final class AppStore: ObservableObject {
    let context: ModelContext
    let syncEngine: SyncEngine

    @Published var today = Day.today()
    @Published var selectedDay = Day.today()
    @Published var syncUi = SyncUi(state: .offline, label: "Not synced yet")
    @Published var quote: Quote?
    @Published var waterOn = WaterReminder.isEnabled
    @Published var selectedGroup: MuscleGroup = .chest
    @Published var lastResult: LogResult?
    @Published var sharingRanks = false
    @Published var darkTheme: Bool {
        didSet { UserDefaults.standard.set(darkTheme, forKey: "dark_theme") }
    }
    @Published var manualHost: String {
        didSet { syncEngine.manualHost = manualHost }
    }

    private var syncing = false

    init(context: ModelContext) {
        let engine = SyncEngine(context: context)
        self.context = context
        self.syncEngine = engine
        self.darkTheme = UserDefaults.standard.bool(forKey: "dark_theme")
        self.manualHost = engine.manualHost
        seedExercisesIfNeeded()
        Task { self.quote = await QuoteClient.fetch() }
    }

    private func save() { try? context.save() }

    // MARK: day / sync

    func refreshToday() { today = Day.today() }
    func selectDay(_ d: String) { selectedDay = d }

    func syncNow() async {
        if syncing { return }
        syncing = true
        syncUi = SyncUi(state: .searching, label: "Searching…")
        switch await syncEngine.sync() {
        case .synced: syncUi = SyncUi(state: .synced, label: "Connected & synced")
        case .notFound: syncUi = SyncUi(state: .offline, label: "Desktop not found")
        case .failed: syncUi = SyncUi(state: .offline, label: "Sync failed")
        }
        syncing = false
    }

    func requestSync() { syncEngine.requestSync() }

    // MARK: tasks

    /// Each mutator returns an error message, or nil on success (same rules as the desktop app).
    func addTask(title: String, details: String, oneOff: Bool) -> String? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "A task needs a title." }
        context.insert(TaskItem(title: t, details: details.trimmingCharacters(in: .whitespacesAndNewlines),
                                createdAt: Day.today(), updatedAt: Iso.now(), isOneOff: oneOff))
        save()
        return nil
    }

    private func task(_ uid: String) -> TaskItem? {
        try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.uid == uid })).first
    }

    func deleteTask(uid: String) {
        guard let t = task(uid) else { return }
        t.isDeleted = true; t.updatedAt = Iso.now()      // soft delete
        save()
    }

    func setCompletion(taskUid: String, day: String, done: Bool) -> String? {
        if Day.isFuture(day) { return "You can't tick off a future day." }
        guard let t = task(taskUid), !t.isDeleted, !t.isOneOff, day >= t.createdAt else {
            return "This task didn't exist on that day."
        }
        let key = Completion.makeKey(taskUid, day)
        if let c = try? context.fetch(FetchDescriptor<Completion>(predicate: #Predicate<Completion> { $0.key == key })).first {
            c.isDeleted = !done; c.updatedAt = Iso.now()
        } else {
            context.insert(Completion(taskUid: taskUid, day: day, updatedAt: Iso.now(), isDeleted: !done))
        }
        save()
        return nil
    }

    /// Tick (or untick) a one-off task. Stored on the task itself so it syncs like any other edit.
    func setOneOffDone(uid: String, done: Bool) {
        guard let t = task(uid), t.isOneOff, !t.isDeleted else { return }
        t.isDone = done; t.updatedAt = Iso.now()
        save()
    }

    // MARK: settings / weight

    func unit() -> String {
        let k = "unit"
        let v = try? context.fetch(FetchDescriptor<SettingEntry>(predicate: #Predicate<SettingEntry> { $0.key == k })).first?.value
        return v == "lb" ? "lb" : "kg"
    }

    func setUnit(_ unit: String) {
        guard unit == "kg" || unit == "lb" else { return }
        let k = "unit"
        if let s = try? context.fetch(FetchDescriptor<SettingEntry>(predicate: #Predicate<SettingEntry> { $0.key == k })).first {
            s.value = unit; s.updatedAt = Iso.now()
        } else {
            context.insert(SettingEntry(key: k, value: unit, updatedAt: Iso.now()))
        }
        save()
    }

    private func weight(_ day: String) -> WeightEntry? {
        try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate<WeightEntry> { $0.day == day })).first
    }

    func setWeight(day: String, value: Double?, unit: String) -> String? {
        guard let value else { return "Enter a valid date and weight." }
        if Day.isFuture(day) { return "You can't log a weight for a future day." }
        let kg = unit == "lb" ? value * kgPerLb : value
        if kg < 20 || kg > 500 { return "That weight looks out of range." }
        if let w = weight(day) { w.kg = kg; w.isDeleted = false; w.updatedAt = Iso.now() }
        else { context.insert(WeightEntry(day: day, kg: kg, updatedAt: Iso.now())) }
        save()
        return nil
    }

    func deleteWeight(day: String) {
        guard let w = weight(day) else { return }
        w.isDeleted = true; w.updatedAt = Iso.now()
        save()
    }

    func latestBodyweightKg() -> Double? {
        let all = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        return all.filter { !$0.isDeleted }.max { $0.day < $1.day }?.kg
    }

    // MARK: water reminders

    func setWater(_ on: Bool) {
        waterOn = on
        Task { await WaterReminder.setEnabled(on) }
    }

    func rescheduleWater() { Task { await WaterReminder.schedule() } }

    // MARK: strength

    private func seedExercisesIfNeeded() {
        let count = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        if count > 0 { return }
        for (i, s) in StrengthEngine.defaults.enumerated() {
            context.insert(Exercise(name: s.name, primaryMuscleGroup: s.group.rawValue, baselineMultiplier: s.multiplier,
                                    usesBodyweight: s.usesBodyweight, order: i))
        }
        save()
    }

    static func windowStartMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000) - Int64(StrengthEngine.windowDays) * 24 * 3600 * 1000
    }

    private func setsSince(_ since: Int64) -> [SetLog] {
        let d = FetchDescriptor<SetLog>(predicate: #Predicate<SetLog> { $0.timestamp >= since && $0.isDeleted == false })
        return (try? context.fetch(d)) ?? []
    }

    private func exercises() -> [Exercise] {
        (try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.order)]))) ?? []
    }

    func deleteSet(uid: String) {
        if let s = try? context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate<SetLog> { $0.uid == uid })).first {
            s.isDeleted = true; s.updatedAt = Iso.now()      // soft delete so the deletion reaches the desktop
            save()
            requestSync()
        }
    }

    /// Validates, stores `sets` identical sets, then reports the rank before and after. `weightInUnit` is in the user's unit.
    func logSets(exercise ex: Exercise, sets: Int, reps: Int, weightInUnit: Double?) -> String? {
        guard let weightInUnit else { return "Enter a weight." }
        if !(1...20).contains(sets) { return "Sets must be between 1 and 20." }
        if !(1...30).contains(reps) { return "Reps must be between 1 and 30." }
        let kg = unit() == "lb" ? weightInUnit * kgPerLb : weightInUnit
        if kg < 0 || kg > 1000 { return "That weight looks out of range." }
        if !ex.usesBodyweight && kg <= 0 { return "Enter a weight above 0." }
        let effective = kg + (ex.usesBodyweight ? (latestBodyweightKg() ?? 0) : 0)
        if effective <= 0 { return "Log your body weight above first, or add weight." }
        guard let group = MuscleGroup(rawValue: ex.primaryMuscleGroup) else { return "Unknown muscle group." }

        let e1 = StrengthEngine.epley(weightKg: effective, reps: reps)
        let all = exercises()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let existing = setsSince(Self.windowStartMs())
        let before = StrengthEngine.groupRanks(exercises: all, sets: existing)
        var added: [SetLog] = []
        for i in 0..<sets {
            let s = SetLog(exerciseName: ex.name, primaryGroup: ex.primaryMuscleGroup, weightKg: kg, reps: reps,
                           timestamp: now + Int64(i), estimatedOneRepMax: e1)
            context.insert(s)
            added.append(s)
        }
        save()
        requestSync()   // push the new sets to the desktop straight away
        let after = StrengthEngine.groupRanks(exercises: all, sets: existing + added)
        let prev = existing.filter { $0.exerciseName == ex.name }.map(\.estimatedOneRepMax).max()
        selectedGroup = group
        guard let afterStanding = after.first(where: { $0.group == group })?.standing else { return nil }
        lastResult = LogResult(
            exerciseName: ex.name, group: group, sets: sets, reps: reps, e1rmKg: e1,
            before: before.first(where: { $0.group == group })?.standing, after: afterStanding,
            newBest: prev == nil || e1 > prev!)
        return nil
    }
}
