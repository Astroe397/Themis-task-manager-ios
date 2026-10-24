import Foundation
import SwiftData

enum SyncResult {
    case synced(String)
    case notFound
    case failed(String)
}

/// Talks to the desktop app over the LAN: pull, apply (last-write-wins), then push local changes.
/// Runs on the main actor against the main ModelContext; the network awaits never block the UI.
@MainActor
final class SyncEngine {
    private let context: ModelContext
    private let defaults = UserDefaults.standard
    private var running = false
    private var queued = false

    init(context: ModelContext) { self.context = context }

    /// Fire-and-forget sync shortly after a local change. Bursts are coalesced.
    func requestSync() {
        if queued { return }
        queued = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            self.queued = false
            _ = await self.sync()
        }
    }

    // MARK: host resolution

    /// "192.168.1.20" or "192.168.1.20:54322"
    var manualHost: String {
        get { defaults.string(forKey: "manual_host") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "manual_host"); defaults.removeObject(forKey: "host") }
    }

    private func parseManual() -> DesktopHost? {
        let s = manualHost
        if s.isEmpty { return nil }
        let parts = s.split(separator: ":")
        guard let h = parts.first else { return nil }
        let port = parts.count > 1 ? (Int(parts[1]) ?? 54322) : 54322
        return DesktopHost(host: String(h), port: port)
    }

    private func makeSession(seconds: TimeInterval) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = seconds
        cfg.timeoutIntervalForResource = seconds
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    private func url(_ h: DesktopHost, _ path: String) -> URL? { URL(string: "http://\(h.host):\(h.port)/\(path)") }

    private func status(_ h: DesktopHost, seconds: TimeInterval) async -> Bool {
        guard let u = url(h, "api/v1/sync/status") else { return false }
        do {
            let (_, resp) = try await makeSession(seconds: seconds).data(from: u)
            return (resp as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        } catch { return false }
    }

    /// Manual address first, then the cached host (fast path), then UDP discovery.
    private func resolve() async -> DesktopHost? {
        if let manual = parseManual() { return manual }
        if let h = defaults.string(forKey: "host") {
            let cached = DesktopHost(host: h, port: defaults.object(forKey: "port") as? Int ?? 54322)
            if await status(cached, seconds: 2) { return cached }
        }
        if let found = await Discovery.find() {
            defaults.set(found.host, forKey: "host"); defaults.set(found.port, forKey: "port")
            return found
        }
        return nil
    }

    // MARK: HTTP

    private func post<Body: Encodable, Resp: Decodable>(_ h: DesktopHost, _ path: String, _ body: Body, type: Resp.Type) async throws -> Resp {
        guard let u = url(h, path) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await makeSession(seconds: 15).data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Resp.self, from: data)
    }

    // MARK: sync

    func sync() async -> SyncResult {
        if running { return .failed("Sync already running") }
        running = true
        defer { running = false }
        do {
            guard let host = await resolve() else { return .notFound }
            let startedAt = Iso.now()
            let since = defaults.string(forKey: "last_synced_at") ?? Iso.epoch

            // Collect local changes first so freshly pulled records aren't echoed straight back.
            let outgoing = collectLocal(since: since)
            let pulled = try await post(host, "api/v1/sync/pull", PullRequest(since: since), type: PullResponse.self)
            if !pulled.ok { return .failed("Pull rejected") }
            applyRemote(pulled)

            // Workouts carry their GPS route, so they travel in their own size-capped requests after everything else.
            var core = outgoing
            core.activities = []
            let pushed = try await post(host, "api/v1/sync/push", core, type: PushResponse.self)
            if !pushed.ok { return .failed("Push rejected") }
            for batch in batchActivities(outgoing.activities) {
                let payload = SyncPayload(activities: batch)
                let sent = try await post(host, "api/v1/sync/push", payload, type: PushResponse.self)
                if !sent.ok { return .failed("Workout push rejected") }
            }

            // Stamp with the time the sync STARTED, so edits made mid-sync are sent next time.
            defaults.set(startedAt, forKey: "last_synced_at")
            return .synced(startedAt)
        } catch {
            // Cached host may be stale (new IP): forget it so the next attempt rediscovers.
            defaults.removeObject(forKey: "host")
            return .failed(error.localizedDescription)
        }
    }

    private func all<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private func collectLocal(since: String) -> SyncPayload {
        var p = SyncPayload()
        p.tasks = all(TaskItem.self).filter { $0.updatedAt >= since }.map {
            TaskDto(uid: $0.uid, title: $0.title, description: $0.details, createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt, isDeleted: $0.isDeleted ? 1 : 0,
                    isOneOff: $0.isOneOff ? 1 : 0, isDone: $0.isDone ? 1 : 0)
        }
        p.completions = all(Completion.self).filter { $0.updatedAt >= since }.map {
            CompletionDto(taskUid: $0.taskUid, day: $0.day, updatedAt: $0.updatedAt, isDeleted: $0.isDeleted ? 1 : 0)
        }
        p.weights = all(WeightEntry.self).filter { $0.updatedAt >= since }.map {
            WeightDto(day: $0.day, kg: $0.kg, updatedAt: $0.updatedAt, isDeleted: $0.isDeleted ? 1 : 0)
        }
        p.settings = all(SettingEntry.self).filter { $0.updatedAt >= since }.map {
            SettingDto(key: $0.key, value: $0.value, updatedAt: $0.updatedAt)
        }
        p.strengthSets = all(SetLog.self).filter { $0.updatedAt >= since }.map {
            StrengthSetDto(id: $0.uid, exerciseName: $0.exerciseName, primaryGroup: $0.primaryGroup,
                           weightKg: $0.weightKg, reps: $0.reps, e1rmKg: $0.estimatedOneRepMax,
                           timestamp: $0.timestamp, updatedAt: $0.updatedAt, isDeleted: $0.isDeleted ? 1 : 0)
        }
        p.activities = collectActivityDtos(since: since)
        return p
    }

    // MARK: workouts

    private struct RoutePoint: Codable { let lat: Double; let lng: Double; let alt: Double }

    private func roundTo(_ v: Double, _ scale: Double) -> Double { (v * scale).rounded() / scale }

    /// Every recorded fix as the desktop's route JSON. Non-finite or out-of-range fixes are dropped.
    private func encodeRoute(_ points: [TrackPoint]) -> String {
        let route = points.filter {
            $0.latitude.isFinite && $0.longitude.isFinite &&
            (-90.0...90.0).contains($0.latitude) && (-180.0...180.0).contains($0.longitude)
        }.map {
            RoutePoint(lat: roundTo($0.latitude, 1e6), lng: roundTo($0.longitude, 1e6),
                       alt: $0.altitude.isFinite ? roundTo($0.altitude, 10) : 0)
        }
        guard let data = try? JSONEncoder().encode(route), let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    /// Finished workouts (including deleted ones, as tombstones) changed since `since`. Unfinished ones never leave the phone.
    private func collectActivityDtos(since: String) -> [ActivityDto] {
        all(Workout.self).filter { $0.status == "FINISHED" && $0.updatedAt >= since }.map { w in
            let uid = w.uid
            let points: [TrackPoint] = w.isDeleted ? [] : {
                var d = FetchDescriptor<TrackPoint>(predicate: #Predicate<TrackPoint> { $0.workoutUid == uid })
                d.sortBy = [SortDescriptor(\.timestamp)]
                return (try? context.fetch(d)) ?? []
            }()
            return ActivityDto(
                id: w.uid, type: "Walking", startTime: w.startedAt,
                endTime: w.endedAt ?? (w.startedAt + w.elapsedMs),
                distanceMeters: w.distanceMeters.isFinite ? max(w.distanceMeters, 0) : 0,
                durationSeconds: w.elapsedMs / 1000, steps: max(w.steps, 0),
                routeJson: w.isDeleted ? "[]" : encodeRoute(points),
                updatedAt: w.updatedAt, isDeleted: w.isDeleted ? 1 : 0)
        }
    }

    /// One request never carries more than about `maxChars` of GPS JSON (the desktop rejects bodies over 25 MB).
    private func batchActivities(_ list: [ActivityDto], maxChars: Int = 4_000_000) -> [[ActivityDto]] {
        var batches: [[ActivityDto]] = []
        var current: [ActivityDto] = []
        var size = 0
        for a in list {
            if !current.isEmpty && size + a.routeJson.count > maxChars {
                batches.append(current); current = []; size = 0
            }
            current.append(a); size += a.routeJson.count
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    // MARK: apply remote (last-write-wins: a remote record only replaces a local one if strictly newer)

    private func applyRemote(_ r: PullResponse) {
        let tasks = Dictionary(all(TaskItem.self).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        var taskUids = Set(tasks.keys)
        for t in r.tasks ?? [] {
            if let local = tasks[t.uid] {
                if t.updatedAt > local.updatedAt {
                    local.title = t.title; local.details = t.description ?? ""; local.createdAt = t.createdAt
                    local.updatedAt = t.updatedAt; local.isDeleted = t.isDeleted != 0
                    local.isOneOff = t.isOneOff != 0; local.isDone = t.isDone != 0
                }
            } else {
                context.insert(TaskItem(uid: t.uid, title: t.title, details: t.description ?? "", createdAt: t.createdAt,
                                        updatedAt: t.updatedAt, isDeleted: t.isDeleted != 0, isOneOff: t.isOneOff != 0,
                                        isDone: t.isDone != 0))
                taskUids.insert(t.uid)
            }
        }

        let comps = Dictionary(all(Completion.self).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for c in r.completions ?? [] {
            guard taskUids.contains(c.taskUid) else { continue }   // tasks are applied first
            if let local = comps[Completion.makeKey(c.taskUid, c.day)] {
                if c.updatedAt > local.updatedAt { local.updatedAt = c.updatedAt; local.isDeleted = c.isDeleted != 0 }
            } else {
                context.insert(Completion(taskUid: c.taskUid, day: c.day, updatedAt: c.updatedAt, isDeleted: c.isDeleted != 0))
            }
        }

        let weights = Dictionary(all(WeightEntry.self).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        for w in r.weights ?? [] {
            if w.kg < 20 || w.kg > 500 { continue }
            if let local = weights[w.day] {
                if w.updatedAt > local.updatedAt { local.kg = w.kg; local.updatedAt = w.updatedAt; local.isDeleted = w.isDeleted != 0 }
            } else {
                context.insert(WeightEntry(day: w.day, kg: w.kg, updatedAt: w.updatedAt, isDeleted: w.isDeleted != 0))
            }
        }

        let settings = Dictionary(all(SettingEntry.self).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for s in r.settings ?? [] {
            if let local = settings[s.key] {
                if s.updatedAt > local.updatedAt { local.value = s.value; local.updatedAt = s.updatedAt }
            } else {
                context.insert(SettingEntry(key: s.key, value: s.value, updatedAt: s.updatedAt))
            }
        }

        var exerciseNames = Set(all(Exercise.self).map(\.name))
        let sets = Dictionary(all(SetLog.self).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        for s in r.strengthSets ?? [] {
            if !s.isValid { continue }
            // Sets travel by exercise name. An unknown name is added so the set isn't lost.
            if !exerciseNames.contains(s.exerciseName) {
                context.insert(Exercise(name: s.exerciseName, primaryMuscleGroup: s.primaryGroup.uppercased(),
                                        baselineMultiplier: 1.0, order: 1000 + exerciseNames.count))
                exerciseNames.insert(s.exerciseName)
            }
            if let local = sets[s.id] {
                if s.updatedAt > local.updatedAt {
                    local.exerciseName = s.exerciseName; local.primaryGroup = s.primaryGroup.uppercased()
                    local.weightKg = s.weightKg; local.reps = s.reps; local.timestamp = s.timestamp
                    local.estimatedOneRepMax = s.e1rmKg; local.updatedAt = s.updatedAt; local.isDeleted = s.isDeleted != 0
                }
            } else {
                context.insert(SetLog(uid: s.id, exerciseName: s.exerciseName, primaryGroup: s.primaryGroup.uppercased(),
                                      weightKg: s.weightKg, reps: s.reps, timestamp: s.timestamp,
                                      estimatedOneRepMax: s.e1rmKg, updatedAt: s.updatedAt, isDeleted: s.isDeleted != 0))
            }
        }
        try? context.save()
    }
}
