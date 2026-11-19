import FuzhouCore
import SwiftUI

struct LiveTable<Controls: View, DrawDock: View>: View {
    let table: TableState
    let names: [Seat: String]
    let latest: TableDiscard?
    let opening: OpeningDeal.Stage?
    let drawingFromReserve: Bool?
    let paused: Bool
    let size: CGSize
    let showsDrawDock: Bool
    let flyingDiscard: Tile.ID?
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let drawDock: () -> DrawDock

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let inset: CGFloat = 10
    private let gap: CGFloat = 6
    private let stripHeight: CGFloat = 24

    var body: some View {
        let width = max(0, size.width - inset * 2)
        let height = max(0, size.height - inset * 2)
        Group {
            if !showsDrawDock, width >= 455, width > height {
                wideTable(width: width, height: height)
            } else {
                seatedTable(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .frame(width: size.width, height: size.height)
        .foregroundStyle(TeaTheme.feltInk)
        .modifier(Felt(walnutRail: true))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table-surface")
    }

    private func seatedTable(width: CGFloat, height: CGFloat) -> some View {
        let endWidth = min(280, width * 0.77)
        let endHeight = min(54, max(38, height * 0.16))
        let playerEndHeight = showsDrawDock ? max(72, endHeight) : endHeight
        let sideWidth = min(108, width * 0.25)
        let middleWidth = max(0, width - 2 * (sideWidth + gap))
        let middleHeight = max(0, height - endHeight - playerEndHeight - stripHeight - gap * 3)

        return VStack(spacing: gap) {
            seatCard(table.viewer.advanced(2), width: endWidth, height: endHeight)
            VStack(spacing: 0) {
                GeometryReader { focus in
                    let sideHeight = min(focus.size.height, 118)
                    HStack(spacing: gap) {
                        seatCard(table.viewer.advanced(1), width: sideWidth, height: sideHeight, vertical: true)
                        discardFocus(width: middleWidth, height: focus.size.height, stacked: true)
                        seatCard(table.viewer.advanced(3), width: sideWidth, height: sideHeight, vertical: true)
                    }
                }
                controls()
            }
            .frame(width: width, height: middleHeight)
            tableStrip(width: width)
            if showsDrawDock {
                let dockWidth = TeaTheme.hitTarget
                let seatWidth = max(0, min(endWidth, width - 2 * (dockWidth + gap)))
                HStack(spacing: gap) {
                    drawDock().frame(width: dockWidth, height: playerEndHeight)
                    seatCard(table.viewer, width: seatWidth, height: endHeight)
                    Color.clear.frame(width: dockWidth, height: 1).accessibilityHidden(true)
                }
                .frame(height: playerEndHeight)
            } else {
                seatCard(table.viewer, width: endWidth, height: endHeight)
            }
        }
    }

    private func wideTable(width: CGFloat, height: CGFloat) -> some View {
        let playersWidth = min(width * 0.56, width - gap - 272)
        let seatWidth = (playersWidth - gap) / 2
        let seatHeight = max(0, (height - gap) / 2)
        let centerWidth = max(0, width - playersWidth - gap)

        return HStack(spacing: gap) {
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                GridRow {
                    seatCard(table.viewer.advanced(1), width: seatWidth, height: seatHeight)
                    seatCard(table.viewer.advanced(2), width: seatWidth, height: seatHeight)
                }
                GridRow {
                    seatCard(table.viewer, width: seatWidth, height: seatHeight)
                    seatCard(table.viewer.advanced(3), width: seatWidth, height: seatHeight)
                }
            }
            VStack(spacing: 0) {
                GeometryReader { focus in
                    discardFocus(width: centerWidth, height: focus.size.height, stacked: false)
                }
                controls()
                tableStrip(width: centerWidth).padding(.top, gap)
            }
            .frame(width: centerWidth, height: height)
        }
    }

    @ViewBuilder
    private func seatCard(_ seat: Seat, width: CGFloat, height: CGFloat, vertical: Bool = false) -> some View {
        if let player = table.players.first(where: { $0.seat == seat }) {
            let acting = opening == nil && !paused && table.step == .turn && table.current == seat
            let won = table.result?.winner == seat
            let highlighted = acting || won
            let dealer = table.dealer == seat
            let wind = table.wind(for: seat)
            let name = name(of: seat)
            let identityWidth = vertical ? width - 8 : min(100, width * 0.49)
            let meldWidth = max(0, vertical ? width - 8 : width - identityWidth - 12)
            let layout = vertical
                ? AnyLayout(VStackLayout(spacing: 4))
                : AnyLayout(HStackLayout(spacing: 4))
            let shape = RoundedRectangle(cornerRadius: 10)

            layout {
                HStack(spacing: 4) {
                    SeatBadge(seat: wind, highlighted: highlighted)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.caption.weight(.semibold))
                        Text(dealer ? "庄 · \(player.score)" : "\(player.score)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(highlighted ? TeaTheme.brass : TeaTheme.muted)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .frame(width: max(0, identityWidth), alignment: vertical ? .center : .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(wind.wind)风，\(name)，\(dealer ? "庄家，" : "")\(won ? "本局赢家，" : acting ? "当前回合，" : "")\(player.score)分")
                .accessibilityIdentifier("seat-score-\(seat.id)")

                meldSummary(player.melds, width: meldWidth, columns: vertical ? 2 : 3)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(name)亮出的牌组")
                    .accessibilityIdentifier("seat-melds-\(seat.id)")
                    .accessibilityHidden(player.melds.isEmpty)
                    .overlay {
                        if seat != table.viewer, !won, player.melds.isEmpty {
                            opponentRack(player)
                        }
                    }
                    .anchorPreference(key: TableAnchors.self, value: .bounds) { [.player(seat): $0] }
            }
            .frame(width: width, height: height)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .background(TeaTheme.feltDark.opacity(highlighted ? 0.94 : 0.72), in: shape)
            .overlay {
                shape.strokeBorder(highlighted ? TeaTheme.brass : TeaTheme.brassShade.opacity(0.35),
                                   lineWidth: won ? 2.5 : acting ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func opponentRack(_ player: TableState.Player) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: opening?.isDealing != true)) { time in
            let landed = opening?.landed(for: player.seat, dealer: table.dealer, at: time.date) ?? player.rackCount
            Canvas { context, size in
                let back = context.resolve(Image("JadeTileBack"))
                for index in 0..<min(FuzhouMatch.rackSize, landed) {
                    let slot = OpeningDeal.opponentSlot(index, in: CGRect(origin: .zero, size: size))
                    OpeningDeal.drawBack(back, in: context, at: slot.center, width: slot.width)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func meldSummary(_ melds: [Meld], width: CGFloat, columns: Int) -> some View {
        let groupWidth = max(0, (width - CGFloat(columns - 1) * 3) / CGFloat(columns))
        let tileWidth = max(0, min(9, (groupWidth - 3) / 4))
        let grid = Array(repeating: GridItem(.fixed(groupWidth), spacing: 3, alignment: .leading), count: columns)

        return ZStack(alignment: .leading) {
            Color.clear.accessibilityHidden(true)
            LazyVGrid(columns: grid, alignment: .leading, spacing: 2) {
                ForEach(melds) { meld in
                    HStack(spacing: 1) {
                        ForEach(meld.tiles) { tile in
                            TileFace(kind: tile.kind).frame(width: tileWidth, height: tileWidth / TileFace.artworkAspectRatio)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(meld.kind.label)，\(meld.tiles.map { $0.kind.spokenName }.joined(separator: "、"))")
                }
            }
        }
        .frame(width: width, height: (tileWidth / TileFace.artworkAspectRatio + 2) * (columns == 2 ? 3 : 2) - 2)
    }

    private func tableStrip(width: CGFloat) -> some View {
        let tileWidth = min(17, max(0, (width - 118) / 6 - 3))
        let winningTile = table.result?.winningTile?.id
        let previous = Array((table.discardTimeline ?? []).filter { $0.id != latest?.id && $0.id != winningTile }.suffix(6))
        return HStack(spacing: 8) {
            wallSources
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(0..<6) { index in
                    Group {
                        if index < previous.count {
                            let discard = previous[index]
                            let claimed = claimedBy(discard) != nil
                            TileFace(kind: discard.tile.kind, gold: table.isGold(discard.tile))
                                .opacity(claimed ? 0.55 : 1)
                                .accessibilityLabel("\(name(of: discard.seat))打出的\(discard.tile.kind.spokenName)\(claimed ? "，已被别人拿走" : "")")
                        } else {
                            Color.clear.accessibilityHidden(true)
                        }
                    }
                    .frame(width: tileWidth, height: min(stripHeight, tileWidth / TileFace.artworkAspectRatio))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("按顺序排列的出牌记录")
        }
        .frame(width: width, height: stripHeight)
    }

    private var wallSources: some View {
        let stacks = min(7, max(0, (table.remaining + 8) / 9))
        let pickup = max(0, stacks - 1)
        return HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(0..<7) { index in
                    ZStack {
                        if index < stacks, opening?.showsWall != false { stack }
                        if index == pickup, drawingFromReserve == false { pickupOutline }
                    }
                    .frame(width: 9, height: 13)
                    .anchorPreference(key: TableAnchors.self, value: .bounds) { anchor in
                        index == pickup ? [.wall: anchor, .wallStack(index): anchor] : [.wallStack(index): anchor]
                    }
                }
            }
            ZStack {
                if opening?.showsWall != false { stack }
                if drawingFromReserve == true { pickupOutline }
            }
            .frame(width: 9, height: 13)
            .anchorPreference(key: TableAnchors.self, value: .bounds) { [.reserve: $0] }
        }
        .accessibilityHidden(true)
    }

    private var stack: some View {
        ZStack {
            TileBack().offset(y: 2)
            TileBack()
        }
    }

    private var pickupOutline: some View {
        RoundedRectangle(cornerRadius: 2).strokeBorder(TeaTheme.brass, lineWidth: 1.5)
    }

    private func discardFocus(width: CGFloat, height: CGFloat, stacked: Bool) -> some View {
        let tileWidth = min(53, width * 0.35, height * (stacked ? 0.34 : 0.50))
        let labelWidth = stacked ? width - 8 : width * 0.55
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        return ZStack {
            if let result = table.result, let winner = result.winner {
                WinningHandReveal(table: table, result: result, winner: winner, name: name(of: winner),
                                  width: max(0, width - 8))
            } else if table.result != nil {
                Text("流局").font(.headline).foregroundStyle(TeaTheme.brass)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("drawn-hand")
            } else if let latest {
                let claim = claimedBy(latest)
                let isGold = table.isGold(latest.tile)
                let owner = "\(name(of: latest.seat))打出"
                let tileName = latest.tile.kind.spokenName
                let detail = claim.map { "\(name(of: $0.seat)) · \($0.kind.label)" } ?? (isGold ? "金牌" : nil)
                let compact = !stacked && height < 54
                let visibleTitle = if compact, let detail { "\(tileName) · \(detail)" } else { tileName }
                layout {
                    TileFace(kind: latest.tile.kind, gold: isGold)
                        .frame(width: tileWidth, height: tileWidth / TileFace.artworkAspectRatio)
                        .anchorPreference(key: TableAnchors.self, value: .bounds) { [.latestDiscard: $0] }
                        .shadow(color: .black.opacity(0.42), radius: 4, y: 3)
                        .opacity(latest.tile.id == flyingDiscard ? 0 : 1)
                        .accessibilityHidden(true)
                    VStack(alignment: stacked ? .center : .leading, spacing: compact ? 1 : 2) {
                        Text(owner).font(.caption2.weight(.semibold)).foregroundStyle(TeaTheme.brass)
                        Text(visibleTitle)
                            .font(.system(compact ? .caption : .subheadline, design: .serif, weight: .bold))
                        if !compact, let detail { Text(detail).font(.caption2).foregroundStyle(TeaTheme.muted) }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: max(0, labelWidth), alignment: stacked ? .center : .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([owner, tileName, detail].compactMap { $0 }.joined(separator: "，"))
                .accessibilityIdentifier("latest-discard")
                .id(latest.id)
                .transition(.opacity)
            } else if opening == nil {
                Text("等待第一张出牌").font(.caption).foregroundStyle(TeaTheme.muted)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: width, height: height)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .transformAnchorPreference(key: TableAnchors.self, value: .bounds) { $0[.center] = $1 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: latest?.id)
    }

    private func name(of seat: Seat) -> String {
        displayName(seat, viewer: table.viewer, names: names)
    }

    private func claimedBy(_ discard: TableDiscard) -> (seat: Seat, kind: MeldKind)? {
        for player in table.players {
            if let meld = player.melds.first(where: { $0.from == discard.seat && $0.tiles.contains(discard.tile) }) {
                return (player.seat, meld.kind)
            }
        }
        return nil
    }
}

struct MeldTiles: View {
    let meld: Meld
    let width: CGFloat
    var showsLabel = true

    var body: some View {
        HStack(spacing: 2) {
            if showsLabel { Text(meld.kind.label).font(.caption2).padding(.trailing, 1) }
            ForEach(meld.tiles) { tile in
                TileFace(kind: tile.kind).frame(width: width, height: width * 1.34)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meld.kind.label)，\(meld.tiles.map { $0.kind.spokenName }.joined(separator: "、"))")
    }
}
