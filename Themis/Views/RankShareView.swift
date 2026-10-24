import SwiftUI
import SwiftData

private let rankTeal = Color(hex: 0x4FB3A1)
private let cardMuted = Color(hex: 0x9FB0B8)

private func cardWeight(_ kg: Double, _ unit: String) -> String { wText(kg, unit) }

struct RankSharePreviewScreen: View {
    @EnvironmentObject var store: AppStore
    @Query(sort: \Exercise.order) private var exercises: [Exercise]
    @Query(filter: #Predicate<SetLog> { $0.isDeleted == false }) private var sets: [SetLog]
    @Query private var settings: [SettingEntry]
    @State private var image: UIImage?

    private var unit: String { settings.first(where: { $0.key == "unit" })?.value == "lb" ? "lb" : "kg" }
    private var ranks: [GroupRank] {
        let since = AppStore.windowStartMs()
        return StrengthEngine.groupRanks(exercises: exercises, sets: sets.filter { $0.timestamp >= since })
    }

    var body: some View {
        let card = RankShareCard(ranks: ranks, unit: unit)
        VStack(spacing: 0) {
            HStack {
                Button { store.sharingRanks = false } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44) }
                Text("Share ranks").font(.themeTitleLarge).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 8)
            Rectangle().fill(Theme.ink).frame(height: 2)
            GeometryReader { geo in
                let s = min(geo.size.width / 360, (geo.size.height - 24) / 640)
                card.frame(width: 360, height: 640).scaleEffect(s)
                    .frame(width: 360 * s, height: 640 * s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Themis muscle ranks", image: Image(uiImage: image))) {
                    Label("Save / Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(AccentButtonStyle())
                .padding(16)
            } else {
                ProgressView().padding(16)
            }
        }
        .background(Theme.bg)
        .task { image = await renderCard(RankShareCard(ranks: ranks, unit: unit)) }
    }
}

/// 9:16 card in the same dark style as the workout card: the strongest group as a hero badge,
/// then all six muscle groups ranked, each with its badge, tier, 1RM and progress to the next tier.
struct RankShareCard: View {
    let ranks: [GroupRank]
    let unit: String

    var body: some View {
        // Strongest first (normalised 1RM is comparable across groups); unranked groups go last.
        let ordered = ranks.sorted { ($0.standing?.normalizedKg ?? -1) > ($1.standing?.normalizedKg ?? -1) }
        let top = ordered.first.flatMap { $0.standing != nil ? $0 : nil }
        let date: String = { let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: Date()) }()

        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B1418), Color(hex: 0x17292F)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text("MUSCLE RANKS").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(rankTeal)
                Text("Best estimated 1RM · last 30 days · \(date)").font(.system(size: 11)).foregroundStyle(cardMuted).padding(.top, 2)

                VStack(spacing: 6) {
                    RankBadge(tier: top?.standing?.tier, size: 104)
                    Text((top?.standing?.tier.label ?? "No ranks yet").uppercased())
                        .font(.system(size: 30, weight: .bold, design: .serif)).tracking(4)
                        .foregroundStyle(top?.standing?.tier.color ?? cardMuted)
                    Text(top.flatMap { t in t.best.map { "\(t.group.label) · 1RM \(cardWeight($0.e1rmKg, unit))" } } ?? "Log a lift to get ranked")
                        .font(.system(size: 12)).foregroundStyle(cardMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 18).padding(.bottom, 14)

                VStack(spacing: 0) {
                    ForEach(ordered) { r in
                        let st = r.standing
                        let tint = st?.tier.color ?? cardMuted.opacity(0.5)
                        HStack(spacing: 10) {
                            RankBadge(tier: st?.tier, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .lastTextBaseline, spacing: 8) {
                                    Text(r.group.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                    Text(st?.tier.label ?? "Unranked").font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
                                }
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(Color.white.opacity(0.12))
                                        Rectangle().fill(tint).frame(width: g.size.width * CGFloat(st?.progress ?? 0))
                                    }
                                }
                                .frame(height: 4)
                            }
                            Text(r.best.map { cardWeight($0.e1rmKg, unit) } ?? "–")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)

                CardBrand().padding(.top, 18)
            }
            .padding(.horizontal, 28).padding(.vertical, 32)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }
}
