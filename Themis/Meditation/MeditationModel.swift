import Foundation
import AVFoundation
import CoreHaptics
import SwiftData
import UIKit

enum MeditationSound: String, CaseIterable, Identifiable {
    case white = "WHITE", rain = "RAIN", brown = "BROWN", pad = "PAD", silent = "SILENT"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .white: return "White Noise"
        case .rain: return "Heavy Rain"
        case .brown: return "Brown Noise"
        case .pad: return "Soft Ambient Pad"
        case .silent: return "Silent"
        }
    }
    var resource: String? {
        switch self {
        case .white: return "ambient_white"
        case .rain: return "ambient_rain"
        case .brown: return "ambient_brown"
        case .pad: return "ambient_pad"
        case .silent: return nil
        }
    }
}

/// `from`/`to` are the circle size (0 = smallest, 1 = largest) at the start and end of the phase.
enum BreathPhase {
    case inhale, holdFull, exhale, holdEmpty
    var label: String {
        switch self {
        case .inhale: return "Breathe in"
        case .holdFull, .holdEmpty: return "Hold"
        case .exhale: return "Breathe out"
        }
    }
    var from: Double { self == .inhale || self == .holdEmpty ? 0 : 1 }
    var to: Double { self == .inhale || self == .holdFull ? 1 : 0 }
}

enum BreathPattern: String, CaseIterable, Identifiable {
    case box = "BOX", calm = "CALM"
    var id: String { rawValue }
    var label: String { self == .box ? "Box 4-4-4-4" : "4-7-8" }
    var steps: [(BreathPhase, Int)] {
        switch self {
        case .box: return [(.inhale, 4), (.holdFull, 4), (.exhale, 4), (.holdEmpty, 4)]
        case .calm: return [(.inhale, 4), (.holdFull, 7), (.exhale, 8)]
        }
    }
}

enum MeditationScreenState { case none, setup, session }

enum MeditationConfig {
    static let totalMs: Int64 = 10 * 60 * 1000
    static let minSavedMs: Int64 = 30_000       // ended-early sessions shorter than this are not stored
    static let fadeInMs = 3_000.0
    static let fadeOutMs = 4_000.0
    static let volume: Float = 0.7
}

/// Owns the whole 10-minute reset: precision timer, breathing phases, ambient audio (AVAudioPlayer) and haptics (CoreHaptics).
/// The timer is derived from the monotonic system uptime, so it stays exact however often the UI redraws.
/// Leaving the app pauses the session; nothing is lost.
@MainActor
final class MeditationModel: ObservableObject {
    @Published var screen: MeditationScreenState = .none
    @Published var running = false
    @Published var paused = false
    @Published var finished = false
    @Published var elapsedMs: Int64 = 0
    @Published var phase: BreathPhase = .inhale
    @Published var phaseSecondsLeft = 0
    @Published var level = 0.0

    @Published var sound: MeditationSound { didSet { defaults.set(sound.rawValue, forKey: "med_sound") } }
    @Published var pattern: BreathPattern { didSet { defaults.set(pattern.rawValue, forKey: "med_pattern") } }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: "med_haptics") } }

    var remainingMs: Int64 { max(MeditationConfig.totalMs - elapsedMs, 0) }

    private let defaults = UserDefaults.standard
    private var context: ModelContext?
    private var player: AVAudioPlayer?
    private var chime: AVAudioPlayer?
    private var timerTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var hapticEngine: CHHapticEngine?
    private var elapsedBase: Int64 = 0       // active ms banked before the current run segment
    private var anchor: TimeInterval = 0     // uptime when the current run segment began
    private var startedAt: Int64 = 0
    private var lastPhaseIndex = -1

    init() {
        sound = MeditationSound(rawValue: UserDefaults.standard.string(forKey: "med_sound") ?? "") ?? .rain
        pattern = BreathPattern(rawValue: UserDefaults.standard.string(forKey: "med_pattern") ?? "") ?? .box
        haptics = UserDefaults.standard.object(forKey: "med_haptics") as? Bool ?? true
    }

    func configure(context: ModelContext) { self.context = context }

    // MARK: navigation

    func openSetup() { if screen == .none { screen = .setup } }
    func closeSetup() { if screen == .setup { screen = .none } }

    /// Starts a session with the saved settings. This is the single tap from the workout summary.
    func start() {
        if screen == .session { return }
        releaseAudio()
        elapsedBase = 0
        startedAt = Int64(Date().timeIntervalSince1970 * 1000)
        lastPhaseIndex = -1
        elapsedMs = 0; level = 0; finished = false; paused = false; running = true
        phase = .inhale; phaseSecondsLeft = 0
        screen = .session
        startAudio()
        startTimer()
    }

    func pause() {
        guard screen == .session, running, !finished else { return }
        elapsedBase += Int64((ProcessInfo.processInfo.systemUptime - anchor) * 1000)
        timerTask?.cancel(); fadeTask?.cancel()
        player?.pause()
        hapticEngine?.stop(completionHandler: nil)
        running = false; paused = true
    }

    func resume() {
        guard screen == .session, !running, !finished else { return }
        running = true; paused = false
        if let p = player { p.volume = 0; p.play() }
        fadeIn()
        startTimer()
    }

    /// Instant, always-available exit. Keeps the stats if the session ran for at least 30 s.
    func endSession() {
        if screen == .session && !finished {
            let spent = elapsedBase + (running ? Int64((ProcessInfo.processInfo.systemUptime - anchor) * 1000) : 0)
            if spent >= MeditationConfig.minSavedMs { save(durationMs: spent, completed: false) }
        }
        close()
    }

    /// Back to wherever the user came from (summary or the main tabs).
    func close() {
        timerTask?.cancel()
        releaseAudio()
        hapticEngine?.stop(completionHandler: nil)
        running = false; paused = false; finished = false
        screen = .none
    }

    // MARK: timer

    private func startTimer() {
        anchor = ProcessInfo.processInfo.systemUptime
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let elapsed = self.elapsedBase + Int64((ProcessInfo.processInfo.systemUptime - self.anchor) * 1000)
                if elapsed >= MeditationConfig.totalMs { self.complete(); break }
                self.tick(elapsed)
                try? await Task.sleep(nanoseconds: 100_000_000)   // UI state refreshes ten times a second
            }
        }
    }

    private func tick(_ elapsed: Int64) {
        let steps = pattern.steps
        let cycleMs = Int64(steps.reduce(0) { $0 + $1.1 }) * 1000
        var pos = elapsed % cycleMs
        var idx = 0
        for (i, s) in steps.enumerated() {
            let d = Int64(s.1) * 1000
            if pos < d { idx = i; break }
            pos -= d
        }
        let (ph, secs) = steps[idx]
        let dur = Double(secs) * 1000
        let p = Double(pos) / dur
        let eased = p * p * (3 - 2 * p)   // smoothstep: the circle eases in and out of each phase
        let lvl = ph.from + (ph.to - ph.from) * eased

        if idx != lastPhaseIndex {
            lastPhaseIndex = idx
            if haptics { buzz(ph) }
        }
        let remaining = Double(MeditationConfig.totalMs - elapsed)
        if remaining < MeditationConfig.fadeOutMs {
            player?.volume = MeditationConfig.volume * Float(remaining / MeditationConfig.fadeOutMs)
        }
        elapsedMs = elapsed
        phase = ph
        phaseSecondsLeft = Int(((dur - Double(pos)) / 1000).rounded(.up))
        level = lvl
    }

    private func complete() {
        running = false; paused = false; finished = true
        elapsedMs = MeditationConfig.totalMs; level = 0
        releaseAudio()
        playChime()
        if haptics { buzzFinish() }
        save(durationMs: MeditationConfig.totalMs, completed: true)
    }

    private func save(durationMs: Int64, completed: Bool) {
        guard let context else { return }
        context.insert(MeditationSession(startedAt: startedAt, durationMs: durationMs, plannedMs: MeditationConfig.totalMs,
                                         completed: completed, sound: sound.rawValue, pattern: pattern.rawValue))
        try? context.save()
    }

    // MARK: audio

    private func configureAudioSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [])
        try? s.setActive(true)
    }

    private func makePlayer(_ resource: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav") else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }

    private func startAudio() {
        guard let res = sound.resource else { return }   // Silent
        configureAudioSession()
        guard let p = makePlayer(res) else { return }
        p.numberOfLoops = -1                              // seamless loop
        p.volume = 0
        p.prepareToPlay()
        p.play()
        player = p
        fadeIn()
    }

    private func fadeIn() {
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            let steps = 30
            for i in 1...steps {
                if Task.isCancelled { return }
                self?.player?.volume = MeditationConfig.volume * Float(i) / Float(steps)
                try? await Task.sleep(nanoseconds: UInt64(MeditationConfig.fadeInMs / Double(steps) * 1_000_000))
            }
        }
    }

    private func playChime() {
        configureAudioSession()
        guard let c = makePlayer("chime") else { return }
        c.volume = 0.8
        c.play()
        chime = c
    }

    private func releaseAudio() {
        fadeTask?.cancel()
        player?.stop()
        player = nil
    }

    // MARK: haptics

    /// (start seconds, duration seconds, intensity 0...1): the same pulse trains the Android build vibrates.
    private func pulses(for phase: BreathPhase) -> [(Double, Double, Float)] {
        switch phase {
        case .inhale: return [(0.00, 0.04, 0.20), (0.12, 0.05, 0.39), (0.25, 0.06, 0.63), (0.39, 0.07, 0.90)]   // rising
        case .exhale: return [(0.00, 0.07, 0.90), (0.15, 0.06, 0.63), (0.29, 0.05, 0.39), (0.42, 0.04, 0.20)]   // falling
        case .holdFull, .holdEmpty: return [(0.00, 0.05, 0.35)]                                                  // one soft tick
        }
    }

    private func buzz(_ phase: BreathPhase) { play(pulses(for: phase)) }
    private func buzzFinish() { play([(0.00, 0.20, 0.20), (0.28, 0.40, 0.40), (0.76, 0.80, 0.63)]) }

    private func play(_ pulses: [(Double, Double, Float)]) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }
        do {
            if hapticEngine == nil {
                let e = try CHHapticEngine()
                e.isAutoShutdownEnabled = true
                e.resetHandler = { [weak e] in _ = try? e?.start() }
                hapticEngine = e
            }
            try hapticEngine?.start()
            let events = pulses.map { (t, d, i) in
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ], relativeTime: t, duration: d)
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let p = try hapticEngine?.makePlayer(with: pattern)
            try p?.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Haptics are a nicety; never let them take the session down.
        }
    }
}
