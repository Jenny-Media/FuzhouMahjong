import FuzhouCore
import SwiftUI

struct MatchResults: View {
    var table: TableState
    var result: RoundResult
    var names: [Seat: String]
    var canAdvance: Bool
    var next: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let winner = result.winner {
                    let name = displayName(winner, viewer: table.viewer, names: names)
                    let payment = result.source.map {
                        "\(displayName($0, viewer: table.viewer, names: names))支付 \(result.points) 分"
                    } ?? "其余三家各付 \(result.points) 分"
                    banner("\(name) · \(winLabel)", value: "\(signed(result.delta(for: table.viewer))) 分",
                           valueLabel: "你的分差", detail: payment)
                    winningTiles(for: winner)
                    scoreGroup("得分明细") {
                        ForEach(result.lines) { line in
                            scoreRow(line.name, amount: "\(line.points)")
                        }
                        scoreRow("合计", amount: "\(result.points)", emphasized: true)
                    }
                } else {
                    banner("牌山已尽", value: "流局", detail: "四家比分不变")
                }

                scoreGroup("本局分差") {
                    ForEach(Seat.allCases) { seat in
                        let delta = result.delta(for: seat)
                        scoreRow("\(table.wind(for: seat).wind) · \(displayName(seat, viewer: table.viewer, names: names))",
                                 amount: signed(delta), color: delta == 0 ? TeaTheme.muted : delta > 0 ? TeaTheme.gain : TeaTheme.loss)
                    }
                }
                scoreGroup(table.matchFinished ? "全场结算" : "当前积分") {
                    ForEach(table.players.sorted { ($0.score, -$0.seat.id) > ($1.score, -$1.seat.id) }) { player in
                        scoreRow(displayName(player.seat, viewer: table.viewer, names: names),
                                 amount: signed(player.score))
                    }
                }
            }
            .padding(TeaTheme.gutter)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if canAdvance {
                    Button(action: next) {
                        Text(table.matchFinished ? "新的一场" : "下一局").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TeaButtonStyle())
                    .accessibilityIdentifier("next-hand")
                } else {
                    Text("等待房主继续").font(.footnote).foregroundStyle(TeaTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: TeaTheme.hitTarget)
                }
            }
            .padding(.horizontal, TeaTheme.gutter)
            .padding(.vertical, 8)
            .background(TeaTheme.canvas)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func winningTiles(for winner: Seat) -> some View {
        let winningTile = result.winningTile
        let melds = table.players.first(where: { $0.seat == winner })?.melds ?? []
        return scoreGroup("胡牌牌型") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(result.winningHand.filter { $0.id != winningTile?.id }) { tile in
                    TileFace(kind: tile.kind, gold: table.isGold(tile)).frame(width: 28, height: 37)
                }
            }
            if let winningTile {
                HStack(spacing: 8) {
                    TileFace(kind: winningTile.kind, gold: table.isGold(winningTile), selected: true)
                        .frame(width: 28, height: 37).accessibilityHidden(true)
                    Text("和牌 · \(winningTile.kind.spokenName)").font(.caption.weight(.semibold))
                }
                .padding(.top, 3)
                .accessibilityIdentifier("winning-tile")
            }
            if !melds.isEmpty {
                Divider().padding(.vertical, 3)
                Text("副露").font(.caption.weight(.semibold))
                ForEach(melds) { meld in MeldTiles(meld: meld, width: 25) }
            }
        }
    }

    private var winLabel: String {
        switch result.kind {
        case .selfDraw: "自摸"
        case .discard: "胡"
        case .robGold: "抢金"
        case nil: ""
        }
    }

    private func banner(_ title: String, value: String, valueLabel: String? = nil, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if let valueLabel { Text(valueLabel).font(.caption).foregroundStyle(TeaTheme.feltInk) }
            Text(value)
                .font(.largeTitle.weight(.bold).monospacedDigit())
                .foregroundStyle(TeaTheme.brass)
            Text(detail).font(.footnote)
        }
        .foregroundStyle(TeaTheme.feltInk)
        .frame(maxWidth: .infinity)
        .padding(20)
        .modifier(Felt())
        .accessibilityElement(children: .combine)
    }

    private func scoreGroup<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            rows()
        }
        .padding(12)
        .background(TeaTheme.surface, in: RoundedRectangle(cornerRadius: TeaTheme.surfaceCorner))
        .overlay { RoundedRectangle(cornerRadius: TeaTheme.surfaceCorner).strokeBorder(TeaTheme.line) }
    }

    private func scoreRow(_ label: String, amount: String, color: Color = TeaTheme.ink,
                          emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(amount)
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .font(.subheadline.weight(emphasized ? .semibold : .regular))
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func signed(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "0"
    }
}
