import Foundation

// is_deleted travels as 0/1 (the desktop's SQLite ints), so it is an Int here, not a Bool.
struct TaskDto: Codable {
    var uid: String
    var title: String
    var description: String?
    var createdAt: String
    var updatedAt: String
    var isDeleted: Int
    var isOneOff: Int
    var isDone: Int
    enum CodingKeys: String, CodingKey {
        case uid, title, description
        case createdAt = "created_at", updatedAt = "updated_at"
        case isDeleted = "is_deleted", isOneOff = "is_one_off", isDone = "is_done"
    }
    init(uid: String, title: String, description: String?, createdAt: String, updatedAt: String,
         isDeleted: Int, isOneOff: Int, isDone: Int) {
        self.uid = uid; self.title = title; self.description = description; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.isDeleted = isDeleted; self.isOneOff = isOneOff; self.isDone = isDone
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(String.self, forKey: .uid)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        isDeleted = try c.decodeIfPresent(Int.self, forKey: .isDeleted) ?? 0
        isOneOff = try c.decodeIfPresent(Int.self, forKey: .isOneOff) ?? 0
        isDone = try c.decodeIfPresent(Int.self, forKey: .isDone) ?? 0
    }
}

struct CompletionDto: Codable {
    var taskUid: String
    var day: String
    var updatedAt: String
    var isDeleted: Int
    enum CodingKeys: String, CodingKey {
        case taskUid = "task_uid", day, updatedAt = "updated_at", isDeleted = "is_deleted"
    }
}

struct WeightDto: Codable {
    var day: String
    var kg: Double
    var updatedAt: String
    var isDeleted: Int
    enum CodingKeys: String, CodingKey { case day, kg, updatedAt = "updated_at", isDeleted = "is_deleted" }
}

struct SettingDto: Codable {
    var key: String
    var value: String
    var updatedAt: String
    enum CodingKeys: String, CodingKey { case key, value, updatedAt = "updated_at" }
}

/// A logged strength set in the desktop's `strength_sets` shape: `id` is the set's UUID and the exercise travels by
/// name + muscle group. Weights are kg, `timestamp` is epoch ms.
struct StrengthSetDto: Codable {
    var id: String
    var exerciseName: String
    var primaryGroup: String
    var weightKg: Double
    var reps: Int
    var e1rmKg: Double
    var timestamp: Int64
    var updatedAt: String
    var isDeleted: Int
    enum CodingKeys: String, CodingKey {
        case id, reps, timestamp
        case exerciseName = "exercise_name", primaryGroup = "primary_group", weightKg = "weight_kg"
        case e1rmKg = "e1rm_kg", updatedAt = "updated_at", isDeleted = "is_deleted"
    }

    /// The same bounds the desktop enforces. A malformed record is skipped rather than applied.
    var isValid: Bool {
        !id.trimmingCharacters(in: .whitespaces).isEmpty &&
        !exerciseName.trimmingCharacters(in: .whitespaces).isEmpty &&
        MuscleGroup(rawValue: primaryGroup.uppercased()) != nil &&
        Iso.isValid(updatedAt) && (0.0...1000.0).contains(weightKg) && e1rmKg > 0 && e1rmKg <= 5000 &&
        (1...30).contains(reps) && timestamp > 0
    }
}

/// A finished workout in the desktop's `activities` shape. `routeJson` is a JSON string of
/// `[{"lat":..,"lng":..,"alt":..}]`; distances are metres, times epoch ms, `durationSeconds` is active time.
struct ActivityDto: Codable {
    var id: String
    var type: String
    var startTime: Int64
    var endTime: Int64
    var distanceMeters: Double
    var durationSeconds: Int64
    var steps: Int
    var routeJson: String
    var updatedAt: String
    var isDeleted: Int
    enum CodingKeys: String, CodingKey {
        case id, type, steps
        case startTime = "start_time", endTime = "end_time", distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds", routeJson = "route_json"
        case updatedAt = "updated_at", isDeleted = "is_deleted"
    }
}

struct SyncPayload: Codable {
    var tasks: [TaskDto] = []
    var completions: [CompletionDto] = []
    var weights: [WeightDto] = []
    var settings: [SettingDto] = []
    var strengthSets: [StrengthSetDto] = []
    var activities: [ActivityDto] = []
    enum CodingKeys: String, CodingKey {
        case tasks, completions, weights, settings, activities
        case strengthSets = "strength_sets"
    }
}

struct PullRequest: Codable { var since: String }

struct PullResponse: Codable {
    var ok: Bool
    var serverTime: String?
    var tasks: [TaskDto]?
    var completions: [CompletionDto]?
    var weights: [WeightDto]?
    var settings: [SettingDto]?
    var strengthSets: [StrengthSetDto]?
    enum CodingKeys: String, CodingKey {
        case ok, tasks, completions, weights, settings
        case serverTime = "server_time", strengthSets = "strength_sets"
    }
}

struct PushResponse: Codable {
    var ok: Bool
    var syncedAt: String?
    var skipped: Int?
    enum CodingKeys: String, CodingKey { case ok, syncedAt = "synced_at", skipped }
}

struct StatusDto: Codable {
    var deviceId: String?
    var lastSyncedAt: String?
    enum CodingKeys: String, CodingKey { case deviceId = "device_id", lastSyncedAt = "last_synced_at" }
}

struct DesktopHost: Equatable {
    var host: String
    var port: Int
}

struct Quote {
    let text: String
    let author: String
}
