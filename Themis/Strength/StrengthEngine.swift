import Foundation
import SwiftUI

enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest = "CHEST", back = "BACK", legs = "LEGS", shoulders = "SHOULDERS", arms = "ARMS", core = "CORE"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .legs: return "Legs"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .core: return "Core"
        }
    }
}

/// Nine tiers. `baseKg` is the bench-press-scale 1RM needed to reach it (Wood = anything below Bronze).
enum RankTier: Int, CaseIterable, Identifiable {
    case wood, bronze, silver, gold, platinum, diamond, champion, titan, olympian
    var id: Int { rawValue }
    var label: String {
        ["Wood", "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Champion", "Titan", "Olympian"][rawValue]
    }
    var colorHex: UInt32 {
        [0x8B5A2B, 0xCD7F32, 0xC0C0C0, 0xFFD700, 0x4ECCA3, 0x9D94FF, 0xD980FA, 0xFF4D4D, 0x48DBFB][rawValue]
    }
    var color: Color { Color(hex: colorHex) }
    var baseKg: Double {
        [0.0, 38.5, 54.4, 65.8, 77.1, 88.5, 102.1, 115.7, 129.3][rawValue]
    }
    var level: Int { rawValue + 1 }
    var next: RankTier? { RankTier(rawValue: rawValue + 1) }
}

struct Standing {
    let tier: RankTier
    let progress: Double          // 0...1 towards tier.next (1 at Olympian)
    let normalizedKg: Double
}

struct ExerciseBest {
    let exerciseName: String
    let group: String
    let e1rmKg: Double
    let normalizedKg: Double
}

struct GroupRank: Identifiable {
    let group: MuscleGroup
    let standing: Standing?
    let best: ExerciseBest?
    var id: String { group.rawValue }
}

struct ExerciseSeed {
    let name: String
    let group: MuscleGroup
    let multiplier: Double
    var usesBodyweight = false
}

enum StrengthEngine {
    static let windowDays = 30

    /// Epley: 1RM = w * (1 + reps / 30). A single rep is the weight itself.
    static func epley(weightKg: Double, reps: Int) -> Double {
        reps <= 1 ? weightKg : weightKg * (1 + Double(min(reps, 30)) / 30.0)
    }

    static func standing(normalizedKg: Double) -> Standing {
        let tier = RankTier.allCases.last { normalizedKg >= $0.baseKg } ?? .wood
        let progress: Double
        if let next = tier.next {
            progress = min(max((normalizedKg - tier.baseKg) / (next.baseKg - tier.baseKg), 0), 1)
        } else { progress = 1 }
        return Standing(tier: tier, progress: progress, normalizedKg: normalizedKg)
    }

    /// Best 1RM per exercise from `sets` (callers pass only the rolling window); each group's best exercise sets its rank.
    static func groupRanks(exercises: [Exercise], sets: [SetLog]) -> [GroupRank] {
        let byName = Dictionary(exercises.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var bests: [ExerciseBest] = []
        for (name, list) in Dictionary(grouping: sets, by: { $0.exerciseName }) {
            guard let ex = byName[name], let e1 = list.map(\.estimatedOneRepMax).max() else { continue }
            bests.append(ExerciseBest(exerciseName: ex.name, group: ex.primaryMuscleGroup, e1rmKg: e1,
                                      normalizedKg: e1 / ex.baselineMultiplier))
        }
        return MuscleGroup.allCases.map { g in
            let best = bests.filter { $0.group == g.rawValue }.max { $0.normalizedKg < $1.normalizedKg }
            return GroupRank(group: g, standing: best.map { standing(normalizedKg: $0.normalizedKg) }, best: best)
        }
    }

    static let defaults: [ExerciseSeed] = [
        ExerciseSeed(name: "Bench Press", group: .chest, multiplier: 1.0),
        ExerciseSeed(name: "Incline Bench Press", group: .chest, multiplier: 0.85),
        ExerciseSeed(name: "Deadlift", group: .back, multiplier: 1.5),
        ExerciseSeed(name: "Barbell Row", group: .back, multiplier: 0.9),
        ExerciseSeed(name: "Lat Pulldown", group: .back, multiplier: 0.85),
        ExerciseSeed(name: "Pull-Ups", group: .back, multiplier: 1.0, usesBodyweight: true),
        ExerciseSeed(name: "Squat", group: .legs, multiplier: 1.35),
        ExerciseSeed(name: "Leg Press", group: .legs, multiplier: 2.2),
        ExerciseSeed(name: "Romanian Deadlift", group: .legs, multiplier: 1.2),
        ExerciseSeed(name: "Overhead Press", group: .shoulders, multiplier: 0.7),
        ExerciseSeed(name: "Lateral Raise", group: .shoulders, multiplier: 0.12),
        ExerciseSeed(name: "Barbell Curl", group: .arms, multiplier: 0.45),
        ExerciseSeed(name: "Triceps Pushdown", group: .arms, multiplier: 0.55),
        ExerciseSeed(name: "Close-Grip Bench Press", group: .arms, multiplier: 0.85),
        ExerciseSeed(name: "Cable Crunch", group: .core, multiplier: 0.6),
        ExerciseSeed(name: "Weighted Sit-Up", group: .core, multiplier: 0.35)
    ]
}
