import SwiftUI
import SwiftData
import MapKit

struct RouteMapView: View {
    let route: [GeoPoint]
    let current: GeoPoint?
    let follow: Bool
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            if route.count >= 2 {
                MapPolyline(coordinates: route.map { $0.coordinate }).stroke(Theme.accent, lineWidth: 5)
            }
            if let first = route.first, route.count >= 2 {
                Annotation("", coordinate: first.coordinate) {
                    Circle().fill(Color(hex: 0x3DDC84)).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let c = current ?? route.last {
                Annotation("", coordinate: c.coordinate) {
                    Circle().fill(Color.blue).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 3))
                }
            }
        }
        .mapStyle(.standard)
        .onAppear { fit() }
        .onChange(of: current) { _, c in
            if follow, let c {
                position = .region(MKCoordinateRegion(center: c.coordinate, latitudinalMeters: 500, longitudinalMeters: 500))
            }
        }
        .onChange(of: route.count) { _, _ in if !follow { fit() } }
    }

    /// Frames the whole route (summary / history), or the last known point.
    private func fit() {
        guard !route.isEmpty else { return }
        let lats = route.map(\.lat), lons = route.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.003),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.003))
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(.themeTitleLarge).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Record runs and walks: live map, distance, time, pace and steps, plus a history of finished workouts.
struct ActivityScreen: View {
    @EnvironmentObject var tracking: TrackingManager
    @Query(filter: #Predicate<Workout> { $0.status == "FINISHED" && $0.isDeleted == false },
           sort: \Workout.startedAt, order: .reverse) private var history: [Workout]
    @State private var confirmStop = false
    @State private var toDelete: Workout?
    @State private var showDenied = false

    private var live: Bool { tracking.status != .idle }

    var body: some View {
        VStack(spacing: 0) {
            RouteMapView(route: live ? tracking.route : [], current: live ? tracking.current : nil,
                         follow: tracking.status == .recording)
                .frame(height: 250)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        VStack(spacing: 12) {
                            HStack {
                                Metric(label: "Distance", value: formatKm(tracking.distanceMeters))
                                Metric(label: "Time", value: formatDuration(tracking.elapsedNow()))
                            }
                            HStack {
                                Metric(label: "Pace", value: formatPace(tracking.paceSecPerKm))
                                Metric(label: "Steps", value: tracking.steps.map(String.init) ?? "–")
                            }
                        }
                    }
                    if live {
                        Text(statusLine).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    controls
                    if !history.isEmpty {
                        Text("Past activities").font(.themeTitleMedium).foregroundStyle(Theme.ink).padding(.top, 8)
                        Text("Tap one for its summary, route map and sharing.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    ForEach(history, id: \.uid) { a in
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(whenText(a.startedAt)).foregroundStyle(Theme.ink)
                                    Text("\(formatKm(a.distanceMeters)) · \(formatDuration(a.elapsedMs))" + (a.steps > 0 ? " · \(a.steps) steps" : ""))
                                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Button("Delete") { toDelete = a }.font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { tracking.openSummary(uid: a.uid) }
                            Divider().overlay(Theme.line)
                        }
                    }
                }
                .padding(16)
            }
        }
        .alert("Finish activity?", isPresented: $confirmStop) {
            Button("Finish") { tracking.stop() }
            Button("Keep going", role: .cancel) {}
        } message: { Text("Your route, distance and steps will be saved.") }
        .alert("Delete activity?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Delete", role: .destructive) { if let a = toDelete { tracking.delete(uid: a.uid) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: { Text("This removes the route and stats from this phone.") }
        .alert("Location is off", isPresented: $showDenied) {
            Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Allow location for Themis in Settings to record routes.") }
        .onChange(of: tracking.locationDenied) { _, denied in if denied { showDenied = true } }
    }

    private var statusLine: String {
        if tracking.status == .paused { return "Paused: GPS is off to save battery" }
        guard let acc = tracking.gpsAccuracy else { return "Waiting for GPS…" }
        return "GPS accuracy ±\(Int(acc)) m"
    }

    @ViewBuilder private var controls: some View {
        switch tracking.status {
        case .idle:
            VStack(spacing: 8) {
                Button("Start activity") { tracking.start() }.buttonStyle(AccentButtonStyle())
                if tracking.hasUnfinished {
                    Button("Resume unfinished workout") { tracking.restore() }.buttonStyle(AccentButtonStyle(filled: false))
                }
            }
        case .recording, .paused:
            HStack(spacing: 8) {
                if tracking.status == .recording {
                    Button("Pause") { tracking.pause() }.buttonStyle(AccentButtonStyle())
                } else {
                    Button("Resume") { tracking.resume() }.buttonStyle(AccentButtonStyle())
                }
                Button("Stop") { confirmStop = true }.buttonStyle(AccentButtonStyle(filled: false, destructive: true))
            }
        }
    }

    private func whenText(_ ms: Int64) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
