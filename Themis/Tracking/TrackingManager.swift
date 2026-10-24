import Foundation
import CoreLocation
import CoreMotion
import SwiftData
import UIKit

enum TrackingStatus { case idle, recording, paused }

/// Owns GPS + pedometer for one workout. Location updates keep running in the background
/// (UIBackgroundModes = location, blue status-bar pill) so a locked phone still records the route.
@MainActor
final class TrackingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: TrackingStatus = .idle
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var steps: Int? = nil              // nil = no step sensor or permission
    @Published private(set) var paceSecPerKm: Double? = nil
    @Published private(set) var gpsAccuracy: Double? = nil
    @Published private(set) var current: GeoPoint? = nil
    @Published private(set) var route: [GeoPoint] = []          // Douglas-Peucker reduced: for drawing only
    @Published private(set) var hasUnfinished = false
    @Published private(set) var locationDenied = false
    @Published var summary: WorkoutSummary? = nil

    // Elapsed active time is measured at `anchor` (system uptime); the UI ticks from there.
    private var elapsedBase: Int64 = 0
    private var anchor: TimeInterval = 0

    private var context: ModelContext?
    var onFinished: (() -> Void)?

    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()
    private let kalman = KalmanLocationFilter()

    private var workoutUid = ""
    private var fullRoute: [GeoPoint] = []
    private var movingMs: Int64 = 0
    private var lastRaw: CLLocation?
    private var lastCounted: GeoPoint?
    private var lastCountedTimeMs: Int64 = 0
    private var segmentStart = true          // first fix after start/resume: no distance across the gap
    private var rejected = 0
    private var window: [(Int64, Double)] = []
    private var stepsBase = 0                // steps banked before the current pedometer segment
    private var segmentSteps = 0
    private var pendingStart = false

    private let maxAccuracyM = 15.0          // reject fuzzy fixes
    private let maxSpeedMS = 12.0            // ~43 km/h: above that it's a GPS jump, not a runner
    private let minStepM = 1.0               // ignore sub-metre drift while standing
    private let movingSpeedMS = 0.5
    private let paceWindowMs: Int64 = 30_000
    private let renderEpsilonM = 3.0
    private let maxConsecutiveRejects = 5

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3                      // never poll with no distance filter
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    func configure(context: ModelContext) {
        self.context = context
        if status == .idle { hasUnfinished = unfinishedWorkout() != nil }
    }

    func elapsedNow() -> Int64 {
        status == .recording ? elapsedBase + Int64(max(ProcessInfo.processInfo.systemUptime - anchor, 0) * 1000) : elapsedBase
    }

    // MARK: commands

    func start() {
        guard status == .idle else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            pendingStart = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationDenied = true
        default:
            locationDenied = false
            beginNew()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let st = self.manager.authorizationStatus
            if self.pendingStart && st != .notDetermined {
                self.pendingStart = false
                if st == .denied || st == .restricted { self.locationDenied = true } else { self.locationDenied = false; self.beginNew() }
            }
        }
    }

    private func beginNew() {
        guard let context else { return }
        resetSession()
        // An earlier workout that was never finished (process death, then the user chose "Start") is kept as finished.
        if let old = unfinishedWorkout() { old.status = "FINISHED"; old.endedAt = nowMs(); old.updatedAt = Iso.now() }
        let w = Workout(startedAt: nowMs())
        context.insert(w)
        try? context.save()
        workoutUid = w.uid
        status = .recording
        anchor = ProcessInfo.processInfo.systemUptime
        hasUnfinished = false
        attachSensors(fresh: true)
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        guard status == .recording else { return }
        elapsedBase = elapsedNow()
        status = .paused
        detach()                                    // no GPS or sensor drain while paused
        persist(status: "PAUSED")
    }

    func resume() {
        guard status == .paused else { return }
        status = .recording
        anchor = ProcessInfo.processInfo.systemUptime
        segmentStart = true; lastRaw = nil; kalman.reset(); window.removeAll(); paceSecPerKm = nil
        attachSensors(fresh: false)                 // steps taken while paused are not counted
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        persist(status: "RECORDING")
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        guard status != .idle, let context else { return }
        elapsedBase = elapsedNow()
        status = .idle
        detach()
        UIApplication.shared.isIdleTimerDisabled = false
        let uid = workoutUid
        if fullRoute.count < 2 {                    // nothing worth keeping, so no summary either
            discard(uid: uid)
        } else {
            persist(status: "FINISHED", endedAt: nowMs())
            onFinished?()
            openSummary(uid: uid)
        }
        try? context.save()
        clearLive()
    }

    /// Process death: rebuild the unfinished workout from SwiftData (paused, so the user chooses when to carry on).
    func restore() {
        guard status == .idle, let w = unfinishedWorkout() else { hasUnfinished = false; return }
        resetSession()
        workoutUid = w.uid
        distanceMeters = w.distanceMeters
        elapsedBase = w.elapsedMs
        movingMs = w.movingTimeMs
        stepsBase = w.steps
        steps = CMPedometer.isStepCountingAvailable() ? w.steps : nil
        fullRoute = loadPoints(uid: w.uid).map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
        route = DouglasPeucker.simplify(fullRoute, epsilonMeters: renderEpsilonM)
        current = fullRoute.last
        status = .paused
        hasUnfinished = false
    }

    func closeSummary() { summary = nil }

    func delete(uid: String) {
        guard let context else { return }
        if let w = fetchWorkout(uid: uid) {
            w.isDeleted = true; w.updatedAt = Iso.now()      // tombstone so the deletion reaches the desktop
            for p in loadPoints(uid: uid) { context.delete(p) }
            try? context.save()
        }
        onFinished?()
        if summary?.uid == uid { summary = nil }
    }

    func openSummary(uid: String) {
        guard let w = fetchWorkout(uid: uid) else { return }
        let pts = loadPoints(uid: uid).map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
        summary = WorkoutSummary(uid: w.uid, startedAt: w.startedAt, distanceMeters: w.distanceMeters,
                                 elapsedMs: w.elapsedMs, movingTimeMs: w.movingTimeMs, steps: w.steps,
                                 route: DouglasPeucker.simplify(pts, epsilonMeters: 3.0))
    }

    // MARK: location

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for loc in locations { self.onFix(loc) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (no fix yet) are normal; the next update retries.
    }

    private func onFix(_ loc: CLLocation) {
        guard status == .recording, let context else { return }
        guard loc.horizontalAccuracy >= 0 else { return }
        gpsAccuracy = loc.horizontalAccuracy
        if loc.horizontalAccuracy > maxAccuracyM { return }                       // too fuzzy to trust
        if loc.speed >= 0 && loc.speed > maxSpeedMS { return }                    // faster than a human can run

        let timeMs = Int64(loc.timestamp.timeIntervalSince1970 * 1000)
        if let prevRaw = lastRaw, !segmentStart {
            let dt = loc.timestamp.timeIntervalSince(prevRaw.timestamp)
            if dt <= 0 { return }
            if prevRaw.distance(from: loc) / dt > maxSpeedMS {                    // GPS teleport
                rejected += 1
                if rejected < maxConsecutiveRejects { return }
                segmentStart = true; kalman.reset()                               // anchor was the bad one: start over
            }
        }
        rejected = 0
        lastRaw = loc

        let here = kalman.process(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                                  accuracyM: loc.horizontalAccuracy, timeMs: timeMs)   // real-time Kalman only
        var inc = 0.0
        var dtSec = 0.0
        if let prev = lastCounted, !segmentStart {
            inc = metres(prev, here)
            if inc < minStepM { return }                                          // stationary jitter
            dtSec = Double(timeMs - lastCountedTimeMs) / 1000.0
        }
        segmentStart = false
        if inc > 0 && dtSec > 0 {
            distanceMeters += inc
            if inc / dtSec >= movingSpeedMS { movingMs += Int64(dtSec * 1000) }
        }
        lastCounted = here
        lastCountedTimeMs = timeMs

        window.append((timeMs, distanceMeters))
        while window.count > 1 && timeMs - window[0].0 > paceWindowMs { window.removeFirst() }
        if let f = window.first {
            let dMeters = distanceMeters - f.1
            let dSec = Double(timeMs - f.0) / 1000.0
            paceSecPerKm = (dMeters >= 5 && dSec > 0) ? dSec / (dMeters / 1000.0) : nil
        }

        // Source of truth: the filtered fix goes straight to SwiftData, un-reduced.
        context.insert(TrackPoint(
            workoutUid: workoutUid, latitude: here.lat, longitude: here.lon,
            altitude: loc.verticalAccuracy >= 0 ? loc.altitude : 0,
            speed: loc.speed >= 0 ? loc.speed : (dtSec > 0 ? inc / dtSec : 0),
            accuracy: loc.horizontalAccuracy, timestamp: timeMs))
        fullRoute.append(here)
        current = here
        route = DouglasPeucker.simplify(fullRoute, epsilonMeters: renderEpsilonM)
        persist(status: "RECORDING")
    }

    // MARK: pedometer

    private func attachSensors(fresh: Bool) {
        if fresh { stepsBase = 0; segmentSteps = 0 }
        segmentSteps = 0
        guard CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() != .denied, CMPedometer.authorizationStatus() != .restricted else {
            steps = nil
            return
        }
        steps = stepsBase
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let n = data?.numberOfSteps.intValue else { return }
            Task { @MainActor in self?.onSteps(n) }
        }
    }

    private func onSteps(_ n: Int) {
        guard status == .recording else { return }
        segmentSteps = n
        steps = stepsBase + n
    }

    private func detach() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        pedometer.stopUpdates()
        if steps != nil { stepsBase += segmentSteps; segmentSteps = 0; steps = stepsBase }
    }

    // MARK: persistence

    private func persist(status newStatus: String, endedAt: Int64? = nil) {
        guard let w = fetchWorkout(uid: workoutUid) else { return }
        w.distanceMeters = distanceMeters
        w.elapsedMs = elapsedBase + (status == .recording ? Int64(max(ProcessInfo.processInfo.systemUptime - anchor, 0) * 1000) : 0)
        w.movingTimeMs = movingMs
        w.steps = steps ?? 0
        w.status = newStatus
        if let endedAt { w.endedAt = endedAt }
        w.updatedAt = Iso.now()
        try? context?.save()
    }

    private func discard(uid: String) {
        guard let context else { return }
        if let w = fetchWorkout(uid: uid) { context.delete(w) }
        for p in loadPoints(uid: uid) { context.delete(p) }
    }

    private func fetchWorkout(uid: String) -> Workout? {
        let d = FetchDescriptor<Workout>(predicate: #Predicate<Workout> { $0.uid == uid })
        return try? context?.fetch(d).first
    }

    private func unfinishedWorkout() -> Workout? {
        var d = FetchDescriptor<Workout>(predicate: #Predicate<Workout> { $0.status != "FINISHED" }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        d.fetchLimit = 1
        return try? context?.fetch(d).first
    }

    private func loadPoints(uid: String) -> [TrackPoint] {
        var d = FetchDescriptor<TrackPoint>(predicate: #Predicate<TrackPoint> { $0.workoutUid == uid })
        d.sortBy = [SortDescriptor(\.timestamp)]
        return (try? context?.fetch(d)) ?? []
    }

    // MARK: helpers

    private func resetSession() {
        distanceMeters = 0; elapsedBase = 0; movingMs = 0
        fullRoute.removeAll(); route.removeAll(); window.removeAll()
        kalman.reset(); stepsBase = 0; segmentSteps = 0; steps = nil
        lastRaw = nil; lastCounted = nil; lastCountedTimeMs = 0
        segmentStart = true; rejected = 0; paceSecPerKm = nil; gpsAccuracy = nil; current = nil
    }

    private func clearLive() {
        distanceMeters = 0; elapsedBase = 0; movingMs = 0
        fullRoute.removeAll(); route.removeAll(); window.removeAll()
        steps = nil; paceSecPerKm = nil; gpsAccuracy = nil; current = nil
        hasUnfinished = unfinishedWorkout() != nil
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func metres(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
    }
}
