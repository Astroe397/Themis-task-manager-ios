import SwiftUI
import SwiftData

/// Top level: the 10-Min Reset sits on top of everything; a workout summary (after Done, or from the history)
/// takes over the screen next; the rank share preview is one step further in. Back always goes one step out.
struct ThemisRoot: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var tracking: TrackingManager
    @EnvironmentObject var meditation: MeditationModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab = 0
    @State private var taskMode = 0           // 0 = daily, 1 = one-off
    @State private var sharingWorkout = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
        }
        .tint(Theme.accent)
        .task(id: scenePhase) {
            // While the app is visible: sync on open/resume, then every 30 s so the desktop dot stays green.
            guard scenePhase == .active else { return }
            store.refreshToday()
            store.rescheduleWater()
            while !Task.isCancelled {
                await store.syncNow()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, meditation.screen == .session, meditation.running { meditation.pause() }
        }
    }

    @ViewBuilder private var content: some View {
        if meditation.screen == .session {
            MeditationSessionView()
        } else if meditation.screen == .setup {
            MeditationSetupView()
        } else if store.sharingRanks && tracking.summary == nil {
            RankSharePreviewScreen()
        } else if let s = tracking.summary {
            if sharingWorkout {
                SocialSharePreviewScreen(summary: s) { sharingWorkout = false }
            } else {
                WorkoutSummaryScreen(
                    summary: s,
                    resetHint: "\(meditation.sound.label) · \(meditation.pattern.label) · haptics \(meditation.haptics ? "on" : "off")",
                    onBack: { sharingWorkout = false; tracking.closeSummary() },
                    onShare: { sharingWorkout = true })
            }
        } else {
            MainScaffold(tab: $tab, taskMode: $taskMode)
        }
    }
}

private struct MainScaffold: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var meditation: MeditationModel
    @Binding var tab: Int
    @Binding var taskMode: Int
    @State private var showAdd = false
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(toast: $toast)
            ZStack(alignment: .bottomTrailing) {
                Group {
                    switch tab {
                    case 0: DashboardScreen { day in store.selectDay(day); tab = 1 }
                    case 1: TasksScreen(mode: $taskMode)
                    case 2: WeightScreen()
                    default: ActivityScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if tab == 1 {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.onAccent).frame(width: 56, height: 56)
                            .background(Theme.accent).clipShape(Circle())
                            .shadow(radius: 3, y: 2)
                    }
                    .padding(20)
                    .accessibilityLabel("Add task")
                }
            }
            Divider()
            HStack(spacing: 0) {
                navItem("Dashboard", "house.fill", 0)
                navItem("Tasks", "checkmark.circle.fill", 1)
                navItem("Weight", "scalemass.fill", 2)
                navItem("Activity", "figure.walk", 3)
                // Shortcut, not a tab: opens the 10-Min Reset setup over the app.
                Button { meditation.openSetup() } label: { navLabel("Reset", "heart.fill", false) }
                    .buttonStyle(.plain)
            }
            .padding(.top, 6)
            .background(Theme.surface)
        }
        .sheet(isPresented: $showAdd) { AddTaskSheet(oneOff: taskMode == 1) }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast).font(.system(size: 14)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.surface).overlay(Capsule().stroke(Theme.line))
                    .clipShape(Capsule()).padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: toast)
    }

    private func navItem(_ title: String, _ icon: String, _ i: Int) -> some View {
        Button { tab = i } label: { navLabel(title, icon, tab == i) }.buttonStyle(.plain)
    }

    private func navLabel(_ title: String, _ icon: String, _ selected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 20))
            Text(title).font(.system(size: 11))
        }
        .foregroundStyle(selected ? Theme.accent : Theme.muted)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
    }
}

private struct TopBar: View {
    @EnvironmentObject var store: AppStore
    @Binding var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Themis").font(.themeHeadline).foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    let on = !store.waterOn
                    store.setWater(on)
                    toast = on ? "Water reminders on (every 30 min)" : "Water reminders off"
                    Task { try? await Task.sleep(nanoseconds: 2_000_000_000); toast = nil }
                } label: {
                    Image(systemName: "bell.fill").font(.system(size: 18))
                        .foregroundStyle(store.waterOn ? Theme.accent : Theme.muted.opacity(0.45))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(store.waterOn ? "Water reminders on. Tap to turn off" : "Water reminders off. Tap to turn on")
                Button { Task { await store.syncNow() } } label: {
                    HStack(spacing: 8) {
                        Circle().fill(dot).frame(width: 10, height: 10)
                        Text(store.syncUi.label).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 4)
            Rectangle().fill(Theme.ink).frame(height: 2)
        }
        .background(Theme.bg)
    }

    private var dot: Color {
        switch store.syncUi.state {
        case .synced: return Color(hex: 0x2F8F5B)
        case .searching: return Color(hex: 0xD9A21B)
        case .offline: return Color(hex: 0xB0412F)
        }
    }
}
