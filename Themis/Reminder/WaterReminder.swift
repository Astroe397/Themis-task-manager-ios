import Foundation
import UserNotifications

/// A "drink water" notification every 30 minutes (on the :00 and :30), quiet from 23:00 until 09:00.
///
/// iOS has no exact-alarm chain like Android, so this schedules the next 60 local notifications ahead of time
/// (iOS keeps at most 64 pending). The app re-fills the queue every time it is opened.
enum WaterReminder {
    private static let prefix = "themis.water."
    private static let quietStartHour = 23
    private static let quietEndHour = 9
    private static let maxPending = 60

    private static let messages = [
        "Take a moment to hydrate.",
        "A glass of water now keeps the focus later.",
        "Sip, stretch, breathe. Then back to it.",
        "Small habits, steady days. Drink some water.",
        "Your future self says thanks for the water."
    ]

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "water_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "water_enabled") }
    }

    static func inQuietHours(_ hour: Int) -> Bool {
        quietStartHour > quietEndHour ? (hour >= quietStartHour || hour < quietEndHour) : (hour >= quietStartHour && hour < quietEndHour)
    }

    /// Next :00/:30 after `date` that is outside quiet hours (skips straight to 09:00 overnight).
    static func nextTrigger(after date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.second = 0
        var next = cal.date(from: comps) ?? date
        let minute = cal.component(.minute, from: next)
        if minute < 30 {
            next = cal.date(bySetting: .minute, value: 30, of: next) ?? next.addingTimeInterval(1800)
        } else {
            next = cal.date(byAdding: .hour, value: 1, to: next) ?? next.addingTimeInterval(3600)
            next = cal.date(bySetting: .minute, value: 0, of: next) ?? next
        }
        if inQuietHours(cal.component(.hour, from: next)) {
            var c = cal.dateComponents([.year, .month, .day], from: next)
            c.hour = quietEndHour; c.minute = 0; c.second = 0
            var morning = cal.date(from: c) ?? next
            if morning <= date { morning = cal.date(byAdding: .day, value: 1, to: morning) ?? morning }
            next = morning
        }
        return next
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Clears and refills the pending queue. Safe to call repeatedly.
    static func schedule() async {
        let center = UNUserNotificationCenter.current()
        await cancelPending()
        guard isEnabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        var date = Date()
        for i in 0..<maxPending {
            date = nextTrigger(after: date)
            let content = UNMutableNotificationContent()
            content.title = "Time to drink water 💧"
            content.body = messages[i % messages.count]
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + String(i), content: content, trigger: trigger))
        }
    }

    static func cancelPending() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func setEnabled(_ on: Bool) async {
        isEnabled = on
        if on { _ = await requestPermission(); await schedule() } else { await cancelPending() }
    }
}
