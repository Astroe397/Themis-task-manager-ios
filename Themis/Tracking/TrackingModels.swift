import Foundation
import CoreLocation

struct GeoPoint: Equatable {
    var lat: Double
    var lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// A finished workout plus its route (Douglas-Peucker reduced: for drawing and sharing only).
struct WorkoutSummary: Identifiable {
    let uid: String
    let startedAt: Int64
    let distanceMeters: Double
    let elapsedMs: Int64
    let movingTimeMs: Int64
    let steps: Int
    let route: [GeoPoint]
    var id: String { uid }

    /// Average pace in seconds per km, on moving time when we have it. Nil if the distance is too short.
    var avgPaceSecPerKm: Double? {
        let ms = movingTimeMs > 0 ? movingTimeMs : elapsedMs
        return distanceMeters < 10 ? nil : (Double(ms) / 1000.0) / (distanceMeters / 1000.0)
    }
}
