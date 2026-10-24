import SwiftUI
import SwiftData

struct TasksScreen: View {
    @Binding var mode: Int
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                chip("Daily", mode == 0) { mode = 0 }
                chip("One-off", mode == 1) { mode = 1 }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            if mode == 0 { DailyTasks() } else { OneOffTasks() }
        }
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
}

private struct TaskRow: View {
    let title: String
    let details: String
    let done: Bool
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button { onToggle(!done) } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24)).foregroundStyle(done ? Theme.accent : Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(done ? Theme.muted : Theme.ink)
                        .strikethrough(done)
                    if !details.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(details).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.top, 10)
                Spacer(minLength: 0)
                Button("Delete", action: onDelete).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }
            .padding(.vertical, 4)
            Divider().overlay(Theme.line)
        }
    }
}

private struct OneOffTasks: View {
    @EnvironmentObject var store: AppStore
    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false && $0.isOneOff == true }, sort: \TaskItem.order) private var items: [TaskItem]
    @State private var showDone = false
    @State private var toDelete: TaskItem?

    var body: some View {
        let open = items.filter { !$0.isDone }
        let done = items.filter { $0.isDone }.sorted { $0.updatedAt > $1.updatedAt }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Do it once, tick it, and it's done for good. These never touch your heatmap, streak or averages.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.top, 4).padding(.bottom, 8)
                Divider().overlay(Theme.line)
                if open.isEmpty {
                    Text("Nothing pending. Tap + to add a one-off task.").foregroundStyle(Theme.muted).padding(.vertical, 18)
                }
                ForEach(open, id: \.uid) { t in
                    TaskRow(title: t.title, details: t.details, done: t.isDone,
                            onToggle: { store.setOneOffDone(uid: t.uid, done: $0) }, onDelete: { toDelete = t })
                }
                if !done.isEmpty {
                    Button("Completed (\(done.count))  \(showDone ? "▲" : "▼")") { showDone.toggle() }
                        .foregroundStyle(Theme.muted).padding(.vertical, 8)
                    if showDone {
                        ForEach(done, id: \.uid) { t in
                            TaskRow(title: t.title, details: t.details, done: t.isDone,
                                    onToggle: { store.setOneOffDone(uid: t.uid, done: $0) }, onDelete: { toDelete = t })
                        }
                    }
                }
                Spacer().frame(height: 88)
            }
            .padding(.horizontal, 16)
        }
        .alert("Delete task?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Delete", role: .destructive) { if let t = toDelete { store.deleteTask(uid: t.uid) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: { Text("Delete “\(toDelete?.title ?? "")”?") }
    }
}

private struct DailyTasks: View {
    @EnvironmentObject var store: AppStore
    @Query(filter: #Predicate<TaskItem> { $0.isDeleted == false && $0.isOneOff == false }, sort: \TaskItem.order) private var tasks: [TaskItem]
    @Query(filter: #Predicate<Completion> { $0.isDeleted == false }) private var completions: [Completion]
    @State private var picking = false
    @State private var toDelete: TaskItem?
    @State private var error: String?

    var body: some View {
        let day = store.selectedDay
        let isToday = day == store.today
        let doneUids = Set(completions.filter { $0.day == day }.map(\.taskUid))
        let visible = tasks.filter { $0.createdAt <= day }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(isToday ? "Today" : Day.weekday(day)).font(.themeTitleLarge).foregroundStyle(Theme.ink)
                        Text(Day.full(day)).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if !isToday { Button("Back to today") { store.selectDay(store.today) }.font(.system(size: 14)) }
                    Button { picking = true } label: { Label("Pick date", systemImage: "calendar").font(.system(size: 14)) }
                }
                .padding(.top, 12)
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.errorRed) }
                Spacer().frame(height: 8)
                Divider().overlay(Theme.line)
                if visible.isEmpty {
                    Text("No tasks yet. Tap + to add your first one.").foregroundStyle(Theme.muted).padding(.vertical, 18)
                }
                ForEach(visible, id: \.uid) { t in
                    TaskRow(title: t.title, details: t.details, done: doneUids.contains(t.uid),
                            onToggle: { on in error = store.setCompletion(taskUid: t.uid, day: day, done: on) },
                            onDelete: { toDelete = t })
                }
                Spacer().frame(height: 88)
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $picking) {
            DatePickerSheet(initial: day) { store.selectDay($0) }
        }
        .alert("Delete task?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Delete", role: .destructive) { if let t = toDelete { store.deleteTask(uid: t.uid) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: { Text("Delete “\(toDelete?.title ?? "")” and its history?") }
    }
}

struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    let onPick: (String) -> Void
    init(initial: String, onPick: @escaping (String) -> Void) {
        _date = State(initialValue: Day.parse(initial)); self.onPick = onPick
    }
    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical).padding()
                .navigationTitle("Pick date").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("OK") { onPick(Day.string(date)); dismiss() } }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AddTaskSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let oneOff: Bool
    @State private var title = ""
    @State private var details = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(oneOff ? "e.g. Renew passport" : "e.g. Read for 20 minutes", text: $title)
                        .onChange(of: title) { _, v in if v.count > 120 { title = String(v.prefix(120)) } }
                    TextField(oneOff ? "Any details (optional)" : "What counts as done?", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text(oneOff ? "Done once, done for good. Doesn't affect your heatmap." : "New tasks count from today onward.")
                }
                if let error { Text(error).foregroundStyle(Theme.errorRed).font(.system(size: 13)) }
            }
            .navigationTitle(oneOff ? "Add a one-off task" : "Add a task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add task") {
                        if let e = store.addTask(title: title, details: details, oneOff: oneOff) { error = e } else { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
