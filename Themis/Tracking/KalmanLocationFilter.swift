import Foundation

/// Real-time GPS smoothing for the incoming fix stream (latitude/longitude, variance-based).
/// `q` is how fast we believe the runner can change position (m/s): higher trusts new fixes more.
/// Use ONLY on the live stream. Douglas-Peucker is for post-processing/rendering and lives elsewhere.
final class KalmanLocationFilter {
    private let q: Double
    private var lat = 0.0
    private var lon = 0.0
    private var variance = -1.0     // < 0 means "no estimate yet"
    private var lastTimeMs: Int64 = 0

    init(qMetresPerSecond: Double = 3) { q = qMetresPerSecond }

    func reset() { variance = -1 }

    func process(latitude: Double, longitude: Double, accuracyM: Double, timeMs: Int64) -> GeoPoint {
        let acc = max(accuracyM, 1)
        if variance < 0 {
            lat = latitude; lon = longitude; variance = acc * acc; lastTimeMs = timeMs
        } else {
            let dt = timeMs - lastTimeMs
            if dt > 0 {   // uncertainty grows with time since the last fix
                variance += Double(dt) * q * q / 1000.0
                lastTimeMs = timeMs
            }
            let k = variance / (variance + acc * acc)   // Kalman gain
            lat += k * (latitude - lat)
            lon += k * (longitude - lon)
            variance = (1 - k) * variance
        }
        return GeoPoint(lat: lat, lon: lon)
    }
}
