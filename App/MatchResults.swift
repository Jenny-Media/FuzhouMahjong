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
                    banner("\(name) · \(winLabel)", value: signed(result.delta(for: table.viewer)), detail: payment)
                    if !result.winningHand.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 25), spacing: 4)], spacing: 4) {
                            ForEach(result.winningHand) { tile in
                                TileFace(kind: tile.kind, gold: table.isGold(tile)).frame(width: 24, height: 31)
                            }
                        }
                        .accessibilityLabel("胡牌牌型")
                    }
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
                if canAdvance {
                    Button(action: next) {
                        Text(table.matchFinished ? "新的一场" : "下一局").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TeaButtonStyle())
                } else {
                    Text("等待房主继续").font(.footnote).foregroundStyle(TeaTheme.muted)
                }
            }
            .padding(TeaTheme.gutter)
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

    private func banner(_ title: String, value: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
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
