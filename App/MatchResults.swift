import FuzhouCore
import SwiftUI

struct MatchResults: View {
    var table: TableState
    var result: RoundResult
    var names: [Seat: String]
    var canAdvance: Bool
    var paused: Bool
    var advanceTitle: String? = nil
    var advanceDetail: String? = nil
    var returnToTable: () -> Void
    var next: () -> Void

    private var waitMessage: String {
        if paused {
            return canAdvance ? "等待牌友重新连接，可返回牌桌查看座位。" : "牌桌已暂停，等待恢复连接。"
        }
        return table.matchFinished ? "等待房主开新一场" : "等待房主开下一局"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let winner = result.winner {
                    let name = displayName(winner, viewer: table.viewer, names: names)
                    let payment = result.source.map {
                        "\(displayName($0, viewer: table.viewer, names: names))付 \(result.points) 分"
                    } ?? "其余三家各付 \(result.points) 分"
                    banner("\(name) · \(result.winTitle)", value: "\(signed(result.delta(for: table.viewer))) 分",
                           valueLabel: "你的积分变化", detail: payment)
                } else {
                    banner("本局无人胡牌", value: "流局", detail: "四家积分不变")
                }

                if let hands = table.settledHands {
                    NavigationLink {
                        SettledHandsReview(table: table, result: result, names: names, hands: hands)
                    } label: {
                        Label("查看四家手牌", systemImage: "rectangle.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TeaButtonStyle(prominent: false))
                    .accessibilityIdentifier("review-settled-hands")
                }

                if let winner = result.winner {
                    winningTiles(for: winner)
                    scoreGroup("每份得分") {
                        ForEach(result.lines) { line in
                            scoreRow(line.name, amount: "\(line.points)")
                        }
                        scoreRow("每份合计", amount: "\(result.points)", emphasized: true)
                            .accessibilityIdentifier("score-total")
                    }
                }

                scoreGroup("本局积分变化") {
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
                    if canAdvance && !paused {
                        Button(action: next) {
                            Text(advanceTitle ?? (table.matchFinished ? "新开一场" : "下一局")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TeaButtonStyle())
                        .accessibilityIdentifier("next-hand")
                    } else {
                        Text(waitMessage)
                            .font(.footnote).foregroundStyle(TeaTheme.muted)
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
        scoreGroup("胡牌的牌组") {
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
}

private struct SettledHandsReview: View {
    let table: TableState
    let result: RoundResult
    let names: [Seat: String]
    let hands: [Seat: [Tile]]
    @State private var seat: Seat

    init(table: TableState, result: RoundResult, names: [Seat: String], hands: [Seat: [Tile]]) {
        self.table = table
        self.result = result
        self.names = names
        self.hands = hands
        _seat = State(initialValue: result.winner ?? table.viewer)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("座位", selection: $seat) {
                    ForEach(Seat.allCases) { seat in
                        Text(table.wind(for: seat).wind)
                            .accessibilityLabel("\(table.wind(for: seat).wind)风，\(displayName(seat, viewer: table.viewer, names: names))")
                            .tag(seat)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settled-seat-picker")

                VStack(alignment: .leading, spacing: 12) {
                    Text("\(table.wind(for: seat).wind)风 · \(displayName(seat, viewer: table.viewer, names: names))")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("settled-seat-name")
                    if seat == result.winner {
                        Text("\(result.winTitle) · \(signed(result.delta(for: seat))) 分")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TeaTheme.brass)
                    }
                    Text("手牌").font(.subheadline.weight(.semibold))
                    tileGrid(hands[seat] ?? [])
                        .accessibilityIdentifier("settled-hand-\(seat.id)")

                    if let player = table.players.first(where: { $0.seat == seat }) {
                        if !player.melds.isEmpty {
                            Text("牌组").font(.subheadline.weight(.semibold))
                            ForEach(player.melds) { meld in
                                MeldTiles(meld: meld, width: 36)
                            }
                        }
                        if let flowers = player.exposedFlowers, !flowers.isEmpty {
                            Text("花牌").font(.subheadline.weight(.semibold))
                            tileGrid(flowers)
                        }
                    }
                }
                .padding(12)
                .teaPanel()
            }
            .padding(TeaTheme.gutter)
            .frame(maxWidth: TeaTheme.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .modifier(HingeSafeContent())
        .teaBackdrop()
        .navigationTitle("四家手牌")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tileGrid(_ tiles: [Tile]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 4)], spacing: 4) {
            ForEach(tiles) { tile in
                let winning = seat == result.winner && tile.id == result.winningTile?.id
                let gold = table.isGold(tile)
                TileFace(kind: tile.kind, gold: gold, selected: winning)
                    .frame(width: 36, height: 36 / TileFace.artworkAspectRatio)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(tile.kind.spokenName)\(gold ? "，金牌" : "")\(winning ? "，胡牌" : "")")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private func signed(_ delta: Int) -> String {
    if delta > 0 { return "+\(delta)" }
    if delta < 0 { return "−\(-delta)" }
    return "0"
}

struct WinningHandReveal<SeatDetails: View>: View {
    @Environment(\.boardStyle) private var board
    let table: TableState
    let result: RoundResult
    let winner: Seat
    let name: String
    let width: CGFloat
    let seatDetails: () -> SeatDetails

    init(table: TableState, result: RoundResult, winner: Seat, name: String, width: CGFloat,
         @ViewBuilder seatDetails: @escaping () -> SeatDetails = { EmptyView() }) {
        self.table = table
        self.result = result
        self.winner = winner
        self.name = name
        self.width = width
        self.seatDetails = seatDetails
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            winnerTitle
                            winnerGain
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        VStack(spacing: 3) {
                            winnerTitle
                            winnerGain
                        }
                    }
                    WinningGroups(table: table, result: result, winner: winner,
                                  boardSize: CGSize(width: width, height: geometry.size.height))
                    seatDetails()
                }
                .padding(.vertical, 3)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("winning-hand-scroll")
        }
        .frame(width: width)
    }

    private var winnerTitle: some View {
        Text("\(name) · \(result.winTitle)")
            .font(width >= 300 ? .headline : .caption.weight(.bold))
            .foregroundStyle(board.accent)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("winning-hand-reveal")
    }

    private var winnerGain: some View {
        Text("\(signed(result.delta(for: winner))) 分")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(board.accent)
            .accessibilityIdentifier("winning-gain")
    }
}

private struct WinningGroups: View {
    let table: TableState
    let result: RoundResult
    let winner: Seat
    let boardSize: CGSize?

    @Environment(\.boardStyle) private var board
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var captionHeight: CGFloat = 13

    private var accent: Color { boardSize == nil ? TeaTheme.brass : board.accent }
    private var accentInk: Color { boardSize == nil ? TeaTheme.brassInk : board.accentInk }
    private var ink: Color { boardSize == nil ? TeaTheme.feltInk : board.ink }
    private var muted: Color { boardSize == nil ? TeaTheme.muted : board.muted }
    private var surface: Color { boardSize == nil ? TeaTheme.feltDark : board.seatSurface }

    var body: some View {
        let labels = result.patterns.filter { $0 != .robGold && $0 != .threeGold }
        VStack(alignment: boardSize == nil ? .leading : .center, spacing: 5) {
            if !labels.isEmpty {
                Text(labels.map(\.title).joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .accessibilityIdentifier("winning-patterns")
            }
            revealedGroups
        }
    }

    @ViewBuilder private var revealedGroups: some View {
        let melds = table.players.first { $0.seat == winner }?.melds ?? []
        if result.patterns == [.threeGold] {
            VStack(alignment: boardSize == nil ? .leading : .center, spacing: 6) {
                Text("自摸时集齐三张金，直接胡牌")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ink)
                    .accessibilityIdentifier("three-gold-explanation")
                HStack(spacing: 4) {
                    ForEach(result.winningHand.filter(table.isGold)) { tile in
                        revealedTile(tile, represents: nil, width: 28, compact: boardSize != nil)
                    }
                }
            }
        } else if let groups = WinningHand.groups(for: result, melds: melds, gold: table.gold?.kind) {
            let gap: CGFloat = 4
            let compact = boardSize != nil
            let wideReveal = (boardSize?.width ?? 0) >= 300
            let labelWidth: CGFloat = typeSize.isAccessibilitySize && (wideReveal || !compact) ? 56 : compact ? 25 : 32
            let minimum: CGFloat = wideReveal ? (typeSize.isAccessibilitySize ? 230 : 150) : 90
            let columns = boardSize.map { max(1, Int(($0.width + gap) / (minimum + gap))) } ?? 1
            let cardWidth = boardSize.map { ($0.width + gap) / CGFloat(columns) - gap } ?? 152
            let largest = CGFloat(groups.map { $0.members.count }.max() ?? 4)
            let roomForTiles = cardWidth - labelWidth - 11 - 2 * (largest - 1)
            let heightLimit = boardSize.map { boardTileWidth(height: $0.height, groups: groups, columns: columns, gap: gap) }
            let maximumTileWidth: CGFloat = wideReveal ? 44 : compact ? 26 : 29
            let heightBasedWidth = typeSize.isAccessibilitySize && wideReveal ? maximumTileWidth : heightLimit ?? 29
            let tileWidth = max(12, min(heightBasedWidth, maximumTileWidth, roomForTiles / largest))
            let grid = [GridItem(.adaptive(minimum: compact ? minimum : typeSize.isAccessibilitySize ? 230 : 152),
                                 spacing: gap, alignment: .topLeading)]

            VStack(alignment: compact ? .center : .leading, spacing: 5) {
                Text("五组牌和一对将牌")
                    .font(compact ? .caption2 : .footnote)
                    .foregroundStyle(muted)
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
            member.represents.map { "\(member.tile.kind.spokenName)当\($0.spokenName)" }
        }
        let shape = RoundedRectangle(cornerRadius: 5)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(group.kind.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(completesHand ? accent : ink)
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
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: shape)
        .overlay { if completesHand { shape.strokeBorder(accent.opacity(0.7)) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.kind.label)
        .accessibilityIdentifier(group.accessibilityID)
    }

    private func revealedTile(_ tile: Tile, represents: TileKind?, width: CGFloat, compact: Bool) -> some View {
        let winning = tile.id == result.winningTile?.id
        let gold = table.isGold(tile)
        return TileFace(kind: tile.kind, gold: gold, selected: winning)
            .frame(width: width, height: width / TileFace.artworkAspectRatio)
            .overlay(alignment: .bottomTrailing) {
                if winning {
                    Text(compact ? "胡" : "胡牌")
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .foregroundStyle(accentInk)
                        .padding(.horizontal, 2)
                        .background(accent, in: RoundedRectangle(cornerRadius: 2))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(winning ? "用这张牌胡牌，" : "")\(tile.kind.spokenName)\(gold ? "，金牌" : "")\(represents.map { "，当作\($0.spokenName)" } ?? "")")
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

extension RoundResult {
    var winTitle: String {
        patterns.contains(.threeGold) ? WinPattern.threeGold.title : kind?.label ?? "胡"
    }
}

extension WinKind {
    var label: String {
        switch self {
        case .selfDraw: "自摸"
        case .discard: "接炮胡"
        case .robGold: "抢金"
        }
    }
}
