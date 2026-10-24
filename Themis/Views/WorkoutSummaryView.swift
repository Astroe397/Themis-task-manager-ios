import SwiftUI

private let cardOrange = Color(hex: 0xFC4C02)      // Strava-style route colour
private let cardMuted = Color(hex: 0x9FB0B8)

private func startedText(_ ms: Int64) -> String {
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
    return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
}

// MARK: summary screen

/// Shown after Done is tapped (the workout is already saved) and when a past activity is opened.
struct WorkoutSummaryScreen: View {
    @EnvironmentObject var meditation: MeditationModel
    let summary: WorkoutSummary
    let resetHint: String
    let onBack: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onBack() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44) }
                Text("Workout summary").font(.themeTitleLarge).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 8)
            Rectangle().fill(Theme.ink).frame(height: 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RouteMapView(route: summary.route, current: nil, follow: false)
                        .frame(height: 260).overlay(Rectangle().stroke(Theme.line))
                    Text(startedText(summary.startedAt)).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    Panel {
                        Text("Final metrics").font(.themeTitleMedium).foregroundStyle(Theme.ink)
                        Spacer().frame(height: 12)
                        HStack {
                            StatBlock(label: "Distance", value: formatKm(summary.distanceMeters))
                            StatBlock(label: "Time", value: formatDuration(summary.elapsedMs))
                        }
                        Spacer().frame(height: 12)
                        HStack {
                            StatBlock(label: "Avg pace", value: formatPace(summary.avgPaceSecPerKm))
                            StatBlock(label: "Steps", value: summary.steps > 0 ? String(summary.steps) : "–")
                        }
                    }
                    Button { onShare() } label: { Label("Share workout", systemImage: "square.and.arrow.up") }
                        .buttonStyle(AccentButtonStyle())
                    Panel {
                        Text("Wind down").font(.themeTitleMedium).foregroundStyle(Theme.ink)
                        Text("Ten quiet minutes of guided breathing to come down after your workout.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.vertical, 6)
                        Button { meditation.start() } label: { Text("10-Min Reset") }
                            .buttonStyle(AccentButtonStyle())
                        Button { meditation.openSetup() } label: {
                            Text("\(resetHint) · Change").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        .padding(.top, 8)
                    }
                    Button("Done") { onBack() }.buttonStyle(AccentButtonStyle(filled: false))
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
    }
}

// MARK: share preview

struct SocialSharePreviewScreen: View {
    let summary: WorkoutSummary
    let onBack: () -> Void
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onBack() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44) }
                Text("Share workout").font(.themeTitleLarge).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 8)
            Rectangle().fill(Theme.ink).frame(height: 2)
            GeometryReader { geo in
                let s = min(geo.size.width / 360, (geo.size.height - 24) / 640)
                SocialShareCard(summary: summary)
                    .frame(width: 360, height: 640)
                    .scaleEffect(s)
                    .frame(width: 360 * s, height: 640 * s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Themis workout", image: Image(uiImage: image))) {
                    Label("Save / Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(AccentButtonStyle())
                .padding(16)
            } else {
                ProgressView().padding(16)
            }
        }
        .background(Theme.bg)
        .task { image = await renderCard(SocialShareCard(summary: summary)) }
    }
}

/// Renders a 360 x 640 pt card at 3x, which is 1080 x 1920 px: Story resolution on every phone.
@MainActor
func renderCard<V: View>(_ view: V) -> UIImage? {
    let r = ImageRenderer(content: view.frame(width: 360, height: 640))
    r.scale = 3
    return r.uiImage
}

/// Strava-style 9:16 card: dark background, glowing orange route, big metrics, branding.
/// The route is drawn directly (no map tiles), which is what makes the snapshot reliable.
struct SocialShareCard: View {
    let summary: WorkoutSummary

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B1418), Color(hex: 0x17292F)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text("WORKOUT COMPLETE").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(cardOrange)
                Text(startedText(summary.startedAt)).font(.system(size: 13)).foregroundStyle(cardMuted).padding(.top, 2)
                RouteArt(route: summary.route).frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 12)
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(String(format: "%.2f", summary.distanceMeters / 1000.0))
                        .font(.system(size: 76, weight: .bold, design: .serif)).foregroundStyle(.white)
                    Text(" km").font(.system(size: 22)).foregroundStyle(cardMuted)
                }
                HStack(alignment: .top) {
                    cardStat("TIME", formatDuration(summary.elapsedMs), nil)
                    cardStat("AVG PACE", formatPace(summary.avgPaceSecPerKm).replacingOccurrences(of: " /km", with: ""), "/km")
                    cardStat("STEPS", summary.steps > 0 ? String(summary.steps) : "–", nil)
                }
                .padding(.top, 14)
                CardBrand().padding(.top, 26)
            }
            .padding(.horizontal, 28).padding(.vertical, 32)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private func cardStat(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(cardMuted)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 24, weight: .bold, design: .serif)).foregroundStyle(.white)
                if let unit { Text(unit).font(.system(size: 11)).foregroundStyle(cardMuted) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardBrand: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.white)
                Image(systemName: "scalemass.fill").font(.system(size: 18)).foregroundStyle(Color(hex: 0x1F6F62))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("THEMIS").font(.system(size: 15, weight: .bold)).tracking(3).foregroundStyle(.white)
                Text("Liberating data. People's app.").font(.system(size: 10)).foregroundStyle(cardMuted)
            }
            Spacer()
        }
    }
}

/// Fits the (already reduced) route into the box, keeping its true shape, with a soft neon glow.
struct RouteArt: View {
    let route: [GeoPoint]

    var body: some View {
        Canvas { ctx, size in
            guard route.count >= 2 else { return }
            let meanLat = route.reduce(0) { $0 + $1.lat } / Double(route.count)
            let kx = cos(meanLat * .pi / 180)           // shrink longitude so shapes aren't stretched
            let xs = route.map { $0.lon * kx }
            let ys = route.map { $0.lat }
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
            let pad = 24.0
            let w = size.width - 2 * pad, h = size.height - 2 * pad
            let spanX = max(maxX - minX, 1e-9), spanY = max(maxY - minY, 1e-9)
            let scale = min(w / spanX, h / spanY)
            let offX = pad + (w - spanX * scale) / 2
            let offY = pad + (h - spanY * scale) / 2
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: offX + (xs[i] - minX) * scale, y: offY + (maxY - ys[i]) * scale)
            }
            var path = Path()
            path.move(to: pt(0))
            for i in 1..<route.count { path.addLine(to: pt(i)) }
            func stroke(_ width: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }
            ctx.stroke(path, with: .color(cardOrange.opacity(0.14)), style: stroke(18))
            ctx.stroke(path, with: .color(cardOrange.opacity(0.32)), style: stroke(10))
            ctx.stroke(path, with: .color(cardOrange), style: stroke(4.5))
            func dot(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
            ctx.fill(dot(pt(0), 7), with: .color(Color(hex: 0x3DDC84)))
            ctx.fill(dot(pt(route.count - 1), 7), with: .color(.white))
            ctx.stroke(dot(pt(route.count - 1), 7), with: .color(cardOrange), lineWidth: 3)
        }
    }
}
