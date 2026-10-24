import Foundation
import SwiftData

/// `uid` is the cross-device identity. Soft deletes (`isDeleted`) let deletions reach the desktop.
@Model
final class TaskItem {
    @Attribute(.unique) var uid: String
    var title: String
    var details: String
    var createdAt: String      // YYYY-MM-DD
    var updatedAt: String      // UTC ISO
    var isDeleted: Bool
    var isOneOff: Bool
    var isDone: Bool           // only meaningful when isOneOff
    var order: Double

    init(uid: String = UUID().uuidString.lowercased(), title: String, details: String = "",
         createdAt: String, updatedAt: String, isDeleted: Bool = false, isOneOff: Bool = false,
         isDone: Bool = false, order: Double = Date().timeIntervalSince1970) {
        self.uid = uid; self.title = title; self.details = details; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.isDeleted = isDeleted; self.isOneOff = isOneOff
        self.isDone = isDone; self.order = order
    }
}

@Model
final class Completion {
    @Attribute(.unique) var key: String      // "<taskUid>|<day>"
    var taskUid: String
    var day: String
    var updatedAt: String
    var isDeleted: Bool

    init(taskUid: String, day: String, updatedAt: String, isDeleted: Bool = false) {
        self.key = Completion.makeKey(taskUid, day)
        self.taskUid = taskUid; self.day = day; self.updatedAt = updatedAt; self.isDeleted = isDeleted
    }
    static func makeKey(_ uid: String, _ day: String) -> String { "\(uid)|\(day)" }
}

@Model
final class WeightEntry {
    @Attribute(.unique) var day: String
    var kg: Double
    var updatedAt: String
    var isDeleted: Bool

    init(day: String, kg: Double, updatedAt: String, isDeleted: Bool = false) {
        self.day = day; self.kg = kg; self.updatedAt = updatedAt; self.isDeleted = isDeleted
    }
}

@Model
final class SettingEntry {
    @Attribute(.unique) var key: String
    var value: String
    var updatedAt: String

    init(key: String, value: String, updatedAt: String) {
        self.key = key; self.value = value; self.updatedAt = updatedAt
    }
}

/// One recorded workout. Progress is rewritten on every GPS fix so a killed process loses nothing.
@Model
final class Workout {
    @Attribute(.unique) var uid: String
    var startedAt: Int64            // epoch ms
    var endedAt: Int64?
    var status: String              // RECORDING | PAUSED | FINISHED
    var distanceMeters: Double
    var elapsedMs: Int64            // active (non-paused) time
    var movingTimeMs: Int64
    var steps: Int
    var updatedAt: String
    var isDeleted: Bool

    init(startedAt: Int64, status: String = "RECORDING") {
        self.uid = UUID().uuidString.lowercased()
        self.startedAt = startedAt; self.endedAt = nil; self.status = status
        self.distanceMeters = 0; self.elapsedMs = 0; self.movingTimeMs = 0; self.steps = 0
        self.updatedAt = Iso.now(); self.isDeleted = false
    }
}

@Model
final class TrackPoint {
    var workoutUid: String
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: Double
    var accuracy: Double
    var timestamp: Int64

    init(workoutUid: String, latitude: Double, longitude: Double, altitude: Double,
         speed: Double, accuracy: Double, timestamp: Int64) {
        self.workoutUid = workoutUid; self.latitude = latitude; self.longitude = longitude
        self.altitude = altitude; self.speed = speed; self.accuracy = accuracy; self.timestamp = timestamp
    }
}

@Model
final class MeditationSession {
    var startedAt: Int64
    var durationMs: Int64
    var plannedMs: Int64
    var completed: Bool
    var sound: String
    var pattern: String

    init(startedAt: Int64, durationMs: Int64, plannedMs: Int64, completed: Bool, sound: String, pattern: String) {
        self.startedAt = startedAt; self.durationMs = durationMs; self.plannedMs = plannedMs
        self.completed = completed; self.sound = sound; self.pattern = pattern
    }
}

/// `primaryMuscleGroup` holds a MuscleGroup raw value. `baselineMultiplier` scales the tier thresholds to the lift
/// (1.0 = bench-press standards). `usesBodyweight`: the lifter's body weight counts towards the load (pull-ups).
@Model
final class Exercise {
    @Attribute(.unique) var name: String
    var primaryMuscleGroup: String
    var baselineMultiplier: Double
    var usesBodyweight: Bool
    var order: Int

    init(name: String, primaryMuscleGroup: String, baselineMultiplier: Double, usesBodyweight: Bool = false, order: Int = 0) {
        self.name = name; self.primaryMuscleGroup = primaryMuscleGroup
        self.baselineMultiplier = baselineMultiplier; self.usesBodyweight = usesBodyweight; self.order = order
    }
}

/// One logged set. `weightKg` is the weight lifted (added weight for bodyweight lifts); the 1RM already includes body weight.
@Model
final class SetLog {
    @Attribute(.unique) var uid: String
    var exerciseName: String
    var primaryGroup: String
    var weightKg: Double
    var reps: Int
    var timestamp: Int64            // epoch ms
    var estimatedOneRepMax: Double
    var updatedAt: String
    var isDeleted: Bool

    init(uid: String = UUID().uuidString.lowercased(), exerciseName: String, primaryGroup: String,
         weightKg: Double, reps: Int, timestamp: Int64, estimatedOneRepMax: Double,
         updatedAt: String = Iso.now(), isDeleted: Bool = false) {
        self.uid = uid; self.exerciseName = exerciseName; self.primaryGroup = primaryGroup
        self.weightKg = weightKg; self.reps = reps; self.timestamp = timestamp
        self.estimatedOneRepMax = estimatedOneRepMax; self.updatedAt = updatedAt; self.isDeleted = isDeleted
    }
}

let allModelTypes: [any PersistentModel.Type] = [
    TaskItem.self, Completion.self, WeightEntry.self, SettingEntry.self, Workout.self,
    TrackPoint.self, MeditationSession.self, Exercise.self, SetLog.self
]
