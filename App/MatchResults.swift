import FuzhouCore
import SwiftUI

struct MatchResults: View {
    var table: TableState
    var result: RoundResult
    var names: [Seat: String]
    var canAdvance: Bool
    var advanceTitle: String? = nil
    var advanceDetail: String? = nil
    var returnToTable: () -> Void
    var next: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let winner = result.winner {
                    let name = displayName(winner, viewer: table.viewer, names: names)
                    let payment = result.source.map {
                        "\(displayName($0, viewer: table.viewer, names: names))支付 \(result.points) 分"
                    } ?? "其余三家各付 \(result.points) 分"
                    banner("\(name) · \(result.kind?.label ?? "胡")", value: "\(signed(result.delta(for: table.viewer))) 分",
                           valueLabel: "你的分差", detail: payment)
                    winningTiles(for: winner)
                    scoreGroup("得分明细") {
                        ForEach(result.lines) { line in
                            scoreRow(line.name, amount: "\(line.points)")
                        }
                        scoreRow("合计", amount: "\(result.points)", emphasized: true)
                            .accessibilityIdentifier("score-total")
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
            .frame(maxWidth: TeaTheme.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if let advanceDetail { Text(advanceDetail).font(.caption).foregroundStyle(TeaTheme.muted) }
                HStack(spacing: 8) {
                    Button("返回牌桌", action: returnToTable)
                        .buttonStyle(TeaButtonStyle(prominent: false))
                        .accessibilityIdentifier("return-to-table")
                    if canAdvance {
                        Button(action: next) {
                            Text(advanceTitle ?? (table.matchFinished ? "新的一场" : "下一局")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TeaButtonStyle())
                        .accessibilityIdentifier("next-hand")
                    } else {
                        Text("等待房主继续").font(.footnote).foregroundStyle(TeaTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: TeaTheme.hitTarget)
                    }
                }
            }
            .padding(.horizontal, TeaTheme.gutter)
            .padding(.vertical, 8)
            .frame(maxWidth: TeaTheme.contentWidth)
            .frame(maxWidth: .infinity)
            .teaFooter()
        }
        .modifier(HingeSafeContent())
    }

    private func winningTiles(for winner: Seat) -> some View {
        scoreGroup("胡牌牌型") {
            WinningGroups(table: table, result: result, winner: winner, boardSize: nil)
        }
    }

    private func banner(_ title: String, value: String, valueLabel: String? = nil, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if let valueLabel { Text(valueLabel).font(.caption).foregroundStyle(TeaTheme.feltInk) }
            Text(value)
                .font(TeaTheme.display.monospacedDigit())
                .foregroundStyle(TeaTheme.brass)
            Text(detail).font(.footnote)
        }
        .foregroundStyle(TeaTheme.feltInk)
        .frame(maxWidth: .infinity)
        .padding(20)
        .modifier(Felt(inlaid: true))
        .accessibilityElement(children: .combine)
    }

    private func scoreGroup<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(TeaTheme.brass)
                .accessibilityAddTraits(.isHeader)
            rows()
        }
        .padding(12)
        .teaPanel()
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

struct WinningHandReveal: View {
    let table: TableState
    let result: RoundResult
    let winner: Seat
    let name: String
    let width: CGFloat
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 6) {
                    Text("\(name) · \(result.kind?.label ?? "胡")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TeaTheme.brass)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("winning-hand-reveal")
                    WinningGroups(table: table, result: result, winner: winner,
                                  boardSize: CGSize(width: width, height: geometry.size.height))
                }
                .padding(.vertical, 3)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("winning-hand-scroll")
        }
        .frame(width: width)
    }
}

private struct WinningGroups: View {
    let table: TableState
    let result: RoundResult
    let winner: Seat
    let boardSize: CGSize?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var captionHeight: CGFloat = 13

    var body: some View {
        let melds = table.players.first { $0.seat == winner }?.melds ?? []
        if let groups = WinningHand.groups(for: result, melds: melds, gold: table.gold?.kind) {
            let gap: CGFloat = 4
            let compact = boardSize != nil
            let labelWidth: CGFloat = compact ? 25 : typeSize.isAccessibilitySize ? 56 : 32
            let minimum: CGFloat = 90
            let columns = boardSize.map { max(1, Int(($0.width + gap) / (minimum + gap))) } ?? 1
            let cardWidth = boardSize.map { ($0.width + gap) / CGFloat(columns) - gap } ?? 152
            let largest = CGFloat(groups.map { $0.members.count }.max() ?? 4)
            let roomForTiles = cardWidth - labelWidth - 11 - 2 * (largest - 1)
            let heightLimit = boardSize.map { boardTileWidth(height: $0.height, groups: groups, columns: columns, gap: gap) }
            let tileWidth = max(12, min(heightLimit ?? 29, compact ? 26 : 29, roomForTiles / largest))
            let grid = [GridItem(.adaptive(minimum: compact ? minimum : typeSize.isAccessibilitySize ? 230 : 152),
                                 spacing: gap, alignment: .topLeading)]

            VStack(alignment: compact ? .center : .leading, spacing: 5) {
                Text("五组牌 ＋ 一对将牌")
                    .font(compact ? .caption2 : .footnote)
                    .foregroundStyle(TeaTheme.muted)
                LazyVGrid(columns: grid, alignment: .leading, spacing: gap) {
                    ForEach(groups) { group in
                        groupCard(group, tileWidth: tileWidth, labelWidth: labelWidth, compact: compact)
                    }
                }
            }
        } else {
            // Some older snapshots only have the recorded tiles.
            let tiles = result.winningHand.filter { $0.id != result.winningTile?.id } +
                [result.winningTile].compactMap { $0 }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 21), spacing: 2)], spacing: 2) {
                ForEach(tiles) { tile in
                    revealedTile(tile, represents: nil, width: 21, compact: boardSize != nil)
                }
            }
            ForEach(melds) { meld in
                MeldTiles(meld: meld, width: 21)
                    .accessibilityIdentifier("revealed-meld-\(meld.id)")
            }
        }
    }

    private func boardTileWidth(height: CGFloat, groups: [WinningHand.Group], columns: Int, gap: CGFloat) -> CGFloat {
        let rows = CGFloat((groups.count + columns - 1) / columns)
        let rowsWithSubstitutions = stride(from: 0, to: groups.count, by: columns).filter { start in
            groups[start..<min(start + columns, groups.count)].contains { group in
                group.members.contains { $0.represents != nil }
            }
        }.count
        let labels = captionHeight * 2 + 15 + CGFloat(rowsWithSubstitutions) * (captionHeight + 2)
        let padding = rows * 6 + (rows - 1) * gap
        return max(15, (height - labels - padding) / rows * TileFace.artworkAspectRatio)
    }

    private func groupCard(_ group: WinningHand.Group, tileWidth: CGFloat, labelWidth: CGFloat, compact: Bool) -> some View {
        let completesHand = group.members.contains { $0.id == result.winningTile?.id }
        let replacements = group.members.compactMap { member in
            member.represents.map { "\(member.tile.kind.spokenName)代\($0.spokenName)" }
        }
        let shape = RoundedRectangle(cornerRadius: 5)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(group.kind.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(completesHand ? TeaTheme.brass : TeaTheme.feltInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: labelWidth, alignment: .leading)
                    .accessibilityHidden(true)
                HStack(spacing: 2) {
                    ForEach(group.members) { member in
                        revealedTile(member.tile, represents: member.represents, width: tileWidth, compact: compact)
                    }
                }
            }
            if !replacements.isEmpty {
                Text(replacements.joined(separator: " · "))
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(TeaTheme.brass)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TeaTheme.feltDark, in: shape)
        .overlay { if completesHand { shape.strokeBorder(TeaTheme.brass.opacity(0.7)) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.kind.label)
        .accessibilityIdentifier(group.accessibilityID)
    }

    private func revealedTile(_ tile: Tile, represents: TileKind?, width: CGFloat, compact: Bool) -> some View {
        let winning = tile.id == result.winningTile?.id
        let gold = table.isGold(tile)
        return TileFace(kind: tile.kind, gold: gold, selected: winning)
            .frame(width: width, height: width / TileFace.artworkAspectRatio)
            .overlay(alignment: .topTrailing) {
                if gold && width < 26 {
                    Text("金")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(TeaTheme.porcelain)
                        .padding(.horizontal, 1)
                        .background(TeaTheme.wood, in: RoundedRectangle(cornerRadius: 2))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if winning {
                    Text(compact ? "和" : "和牌")
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .foregroundStyle(TeaTheme.brassInk)
                        .padding(.horizontal, 2)
                        .background(TeaTheme.brass, in: RoundedRectangle(cornerRadius: 2))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(winning ? "和牌，" : "")\(tile.kind.spokenName)\(gold ? "，金牌" : "")\(represents.map { "，代\($0.spokenName)" } ?? "")")
            .accessibilityIdentifier(winning ? "revealed-winning-tile" : "revealed-tile-\(tile.id)")
    }
}

private extension WinningHand.Group {
    var accessibilityID: String {
        switch kind {
        case .meld: "revealed-meld-\(id)"
        case .pair: "winning-pair"
        case .sequence, .triplet: "winning-set-\(id)"
        }
    }
}

private extension WinningHand.Group.Kind {
    var label: String {
        switch self {
        case .pair: "将牌"
        case .sequence: "顺子"
        case .triplet: "刻子"
        case .meld(let kind): kind.label
        }
    }
}

extension WinKind {
    var label: String {
        switch self {
        case .selfDraw: "自摸"
        case .discard: "胡"
        case .robGold: "抢金"
        }
    }
}
