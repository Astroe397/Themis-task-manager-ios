import SwiftUI
import SwiftData

private let calmBg = Color(hex: 0x0D1417)
private let calmText = Color(hex: 0xC9D6DA)
private let calmMuted = Color(hex: 0x7F9097)
private let calmTeal = Color(hex: 0x3E8C7F)

/// Setup: sound, breathing pattern, haptics. One tap starts the session.
struct MeditationSetupView: View {
    @EnvironmentObject var meditation: MeditationModel
    @Query(filter: #Predicate<MeditationSession> { $0.completed == true }) private var completed: [MeditationSession]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { meditation.closeSetup() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44) }
                Text("10-Min Reset").font(.themeTitleLarge).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 8)
            Rectangle().fill(Theme.ink).frame(height: 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("A quiet, guided way to come down after a workout: follow the circle, or just feel the vibration.")
                        .foregroundStyle(Theme.muted)
                    if !completed.isEmpty {
                        Text("\(completed.count) reset\(completed.count == 1 ? "" : "s") completed")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    Text("Sound").font(.themeTitleMedium).foregroundStyle(Theme.ink)
                    ForEach(MeditationSound.allCases) { s in
                        Button { meditation.sound = s } label: {
                            HStack {
                                Image(systemName: meditation.sound == s ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(meditation.sound == s ? Theme.accent : Theme.muted)
                                Text(s.label).foregroundStyle(Theme.ink)
                                Spacer()
                            }
                            .padding(.vertical, 4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Breathing").font(.themeTitleMedium).foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        ForEach(BreathPattern.allCases) { p in
                            Button(p.label) { meditation.pattern = p }
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(meditation.pattern == p ? Theme.ink : Theme.muted)
                                .background(meditation.pattern == p ? Theme.l1 : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Toggle(isOn: $meditation.haptics) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Haptic guidance").font(.themeTitleMedium).foregroundStyle(Theme.ink)
                            Text("Rising pulses as you breathe in, falling as you breathe out. Works with your eyes closed.")
                                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.accent)
                    Button("Start 10-Min Reset") { meditation.start() }.buttonStyle(AccentButtonStyle()).padding(.top, 8)
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
    }
}

private func clock(_ ms: Int64) -> String {
    let s = Int((Double(ms) / 1000).rounded(.up))
    return String(format: "%02d:%02d", s / 60, s % 60)
}

/// The session. Screen stays on while it is visible; leaving the app pauses it; End session is always one tap away.
struct MeditationSessionView: View {
    @EnvironmentObject var meditation: MeditationModel

    var body: some View {
        let progress = min(max(Double(meditation.elapsedMs) / Double(MeditationConfig.totalMs), 0), 1)
        VStack(spacing: 0) {
            Text("CALMING RESET").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(calmMuted)
            Text(meditation.finished ? "00:00" : clock(meditation.remainingMs))
                .font(.system(size: 44, weight: .light, design: .serif)).foregroundStyle(calmText).padding(.top, 4)
                .accessibilityLabel("Time left \(clock(meditation.remainingMs))")

            ZStack {
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let maxR = 130.0, ringR = 150.0
                    func circle(_ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
                    ctx.stroke(circle(ringR), with: .color(calmMuted.opacity(0.18)), lineWidth: 3)   // completion ring
                    var arc = Path()
                    arc.addArc(center: c, radius: ringR, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
                    ctx.stroke(arc, with: .color(calmTeal.opacity(0.8)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    if !meditation.finished {
                        let r = maxR * (0.42 + 0.58 * meditation.level)
                        ctx.stroke(circle(maxR), with: .color(calmMuted.opacity(0.22)), lineWidth: 1.5)
                        ctx.fill(circle(r * 1.14), with: .color(calmTeal.opacity(0.10)))               // soft halo
                        ctx.fill(circle(r), with: .color(calmTeal.opacity(0.50)))
                        ctx.stroke(circle(r), with: .color(calmTeal.opacity(0.90)), lineWidth: 2.5)
                    }
                }
                .frame(width: 320, height: 320)
                .animation(.linear(duration: 0.12), value: meditation.level)
                center
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if meditation.finished {
                Button("Done") { meditation.close() }.buttonStyle(CalmButtonStyle(filled: true))
            } else {
                VStack(spacing: 10) {
                    if meditation.paused { Button("Resume") { meditation.resume() }.buttonStyle(CalmButtonStyle(filled: true)) }
                    Button("End session") { meditation.endSession() }.buttonStyle(CalmButtonStyle(filled: false))
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(calmBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }     // screen stays on while the session shows
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder private var center: some View {
        if meditation.finished {
            VStack(spacing: 6) {
                Text("Session Complete").font(.system(size: 24, weight: .bold, design: .serif)).foregroundStyle(calmText)
                Text("10m Calming Reset").font(.system(size: 15)).foregroundStyle(calmMuted)
            }
        } else if meditation.paused {
            Text("Paused").font(.system(size: 24, design: .serif)).foregroundStyle(calmText)
        } else {
            VStack(spacing: 4) {
                Text(meditation.phase.label).font(.system(size: 22, design: .serif)).foregroundStyle(calmText).multilineTextAlignment(.center)
                Text("\(meditation.phaseSecondsLeft)").font(.system(size: 18)).foregroundStyle(calmMuted)
            }
        }
    }
}

private struct CalmButtonStyle: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(filled ? Color.white : calmText)
            .background(filled ? calmTeal : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(filled ? Color.clear : calmMuted.opacity(0.5), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
