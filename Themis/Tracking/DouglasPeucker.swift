import Foundation

/// Polyline reduction for DRAWING a route or exporting a finished one.
/// Never write its output back to the database: SwiftData keeps every filtered fix.
enum DouglasPeucker {
    static func simplify(_ points: [GeoPoint], epsilonMeters: Double) -> [GeoPoint] {
        let n = points.count
        if n < 3 { return points }
        // Local flat projection in metres around the first point; accurate enough for a workout-sized area.
        let mx = 111_320.0 * cos(points[0].lat * .pi / 180)
        let my = 110_540.0
        let x = points.map { ($0.lon - points[0].lon) * mx }
        let y = points.map { ($0.lat - points[0].lat) * my }

        var keep = [Bool](repeating: false, count: n)
        keep[0] = true; keep[n - 1] = true
        var stack: [(Int, Int)] = [(0, n - 1)]      // iterative: a long run must not overflow the call stack
        while let (s, e) = stack.popLast() {
            var worst = -1.0
            var idx = -1
            if e > s + 1 {
                for i in (s + 1)..<e {
                    let d = distToSegment(x[i], y[i], x[s], y[s], x[e], y[e])
                    if d > worst { worst = d; idx = i }
                }
            }
            if idx != -1 && worst > epsilonMeters {
                keep[idx] = true
                stack.append((s, idx))
                stack.append((idx, e))
            }
        }
        return points.enumerated().filter { keep[$0.offset] }.map { $0.element }
    }

    private static func distToSegment(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return hypot(px - ax, py - ay) }
        let t = min(max(((px - ax) * dx + (py - ay) * dy) / len2, 0), 1)
        return hypot(px - (ax + t * dx), py - (ay + t * dy))
    }
}
