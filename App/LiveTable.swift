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
    let flyingClaim: Tile.ID?
    let onOfferedTileFrame: (Tile.ID, CGRect) -> Void
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let drawDock: () -> DrawDock

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardStyle) private var board
    @Environment(\.tileStyle) private var tileStyle

    @State private var inspectedSeat: Seat?

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
        .foregroundStyle(board.ink)
        .modifier(Felt(gameTable: true))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table-surface")
        .sheet(item: $inspectedSeat) { seat in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let player = table.players.first(where: { $0.seat == seat }) {
                            Text("\(table.wind(for: seat).wind)风 · \(player.score)分 · 花牌 \(player.flowerCount)张")
                                .font(.subheadline).foregroundStyle(TeaTheme.muted)
                            if player.melds.isEmpty { Text("还没有亮出的牌组") }
                            ForEach(player.melds) { meld in
                                MeldTiles(meld: meld, width: 40)
                                    .accessibilityIdentifier("inspected-meld-\(meld.id)")
                            }
                        }
                    }
                    .padding(TeaTheme.gutter)
                    .frame(maxWidth: TeaTheme.contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .modifier(HingeSafeContent())
                .teaBackdrop()
                .navigationTitle("\(name(of: seat))的亮牌")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { inspectedSeat = nil } } }
            }
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
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
                    Color.clear.frame(width: dockWidth, height: 1).accessibilityHidden(true)
                    seatCard(table.viewer, width: seatWidth, height: endHeight)
                    drawDock().frame(width: dockWidth, height: playerEndHeight)
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
        let seatHeight = max(0, (height - stripHeight - gap * 2) / 2)
        let centerWidth = max(0, width - playersWidth - gap)

        return HStack(spacing: gap) {
            VStack(spacing: gap) {
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
                tableStrip(width: playersWidth)
            }
            VStack(spacing: 0) {
                GeometryReader { focus in
                    discardFocus(width: centerWidth, height: focus.size.height, stacked: false)
                }
                controls()
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
                    SeatBadge(seat: wind, highlighted: highlighted, board: board)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.caption.weight(.semibold))
                        HStack(spacing: 2) {
                            Text(dealer ? "庄 · \(player.score)" : "\(player.score)")
                            if !player.melds.isEmpty { Image(systemName: "magnifyingglass") }
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(highlighted ? board.accent : board.muted)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .frame(width: max(0, identityWidth), alignment: vertical ? .center : .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(wind.wind)风，\(name)，\(dealer ? "庄家，" : "")\(won ? "本局赢家，" : acting ? "当前回合，" : "")\(player.score)分")
                .accessibilityIdentifier("seat-score-\(seat.id)")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("查看这位玩家的亮牌")
                .accessibilityAction { inspectedSeat = seat }

                let rackHeight = max(1, vertical ? height - 40 : height - 6)
                VStack(alignment: .leading, spacing: 2) {
                    if player.melds.isEmpty {
                        if seat != table.viewer, !won {
                            opponentRack(player)
                        }
                    } else {
                        let showsBacks = seat != table.viewer && !won && player.rackCount > 0
                        if showsBacks {
                            smallRack(count: player.rackCount, width: meldWidth)
                                .frame(height: 8)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("手牌 \(player.rackCount) 张")
                                .accessibilityIdentifier("concealed-rack-\(seat.id)")
                        }
                        meldSummary(player.melds, width: meldWidth, height: rackHeight - (showsBacks ? 10 : 0))
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("\(name)亮出的牌组")
                            .accessibilityIdentifier("seat-melds-\(seat.id)")
                    }
                }
                .frame(width: meldWidth, height: rackHeight)
                .transformAnchorPreference(key: TableAnchors.self, value: .bounds) { $0[.player(seat)] = $1 }
            }
            .frame(width: width, height: height)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .background(board.seatSurface.opacity(highlighted ? 0.94 : 0.72), in: shape)
            .overlay {
                shape.strokeBorder(board.accent.opacity(highlighted ? 1 : 0.34),
                                   lineWidth: won ? 2.5 : acting ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { inspectedSeat = seat }
            .accessibilityElement(children: .contain)
        }
    }

    private func smallRack(count: Int, width: CGFloat) -> some View {
        Canvas { context, size in
            let back = context.resolve(Image(decorative: tileStyle.backArtwork))
            let tileWidth = min(size.height / 1.4, width / CGFloat(max(count, 1)))
            for index in 0..<count {
                OpeningDeal.drawBack(back, in: context,
                                     at: CGPoint(x: (CGFloat(index) + 0.5) * tileWidth, y: size.height / 2),
                                     width: tileWidth)
            }
        }
    }

    private func opponentRack(_ player: TableState.Player) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: opening?.isDealing != true)) { time in
            let landed = opening?.landed(for: player.seat, dealer: table.dealer, at: time.date) ?? player.rackCount
            Canvas { context, size in
                let back = context.resolve(Image(decorative: tileStyle.backArtwork))
                for index in 0..<min(FuzhouMatch.rackSize, landed) {
                    let slot = OpeningDeal.opponentSlot(index, in: CGRect(origin: .zero, size: size))
                    OpeningDeal.drawBack(back, in: context, at: slot.center, width: slot.width)
                }
                if player.seat == table.dealer, table.isOpeningLayout, table.lastDraw?.isOpeningDeal == true,
                   opening?.dealerTileLanded(at: time.date) ?? true {
                    let extra = OpeningDeal.opponentDealerSlot(in: CGRect(origin: .zero, size: size))
                    OpeningDeal.drawBack(back, in: context, at: extra.center, width: extra.width)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func meldSummary(_ melds: [Meld], width: CGFloat, height: CGFloat) -> some View {
        let largestSet = melds.map(\.tiles.count).max() ?? 4
        func faceWidth(columns: Int) -> CGFloat {
            let rows = (melds.count + columns - 1) / columns
            let cell = (width - CGFloat(columns - 1) * 3) / CGFloat(columns)
            let rowHeight = (height - CGFloat(rows - 1) * 2) / CGFloat(rows)
            return max(0, min(22, (cell - CGFloat(largestSet - 1)) / CGFloat(largestSet),
                              rowHeight * TileFace.artworkAspectRatio))
        }
        let columns = (1...melds.count).max { faceWidth(columns: $0) < faceWidth(columns: $1) } ?? 1
        let groupWidth = max(0, (width - CGFloat(columns - 1) * 3) / CGFloat(columns))
        let tileWidth = faceWidth(columns: columns)
        let grid = Array(repeating: GridItem(.fixed(groupWidth), spacing: 3, alignment: .leading), count: columns)

        return ZStack(alignment: .leading) {
            Color.clear.accessibilityHidden(true)
            LazyVGrid(columns: grid, alignment: .leading, spacing: 2) {
                ForEach(melds) { meld in
                    HStack(spacing: 1) {
                        ForEach(meld.tiles) { tile in
                            TileFace(kind: tile.kind)
                                .frame(width: tileWidth, height: tileWidth / TileFace.artworkAspectRatio)
                                .opacity(tile.id == flyingClaim ? 0 : 1)
                                .anchorPreference(key: TableAnchors.self, value: .bounds) { [.meldTile(tile.id): $0] }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(meld.kind.label)，\(meld.tiles.map { $0.kind.spokenName }.joined(separator: "、"))")
                    .accessibilityIdentifier("table-meld-\(meld.id)")
                }
            }
        }
        .frame(width: width, height: max(0, height))
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
        RoundedRectangle(cornerRadius: 2).strokeBorder(board.accent, lineWidth: 1.5)
    }

    private func discardFocus(width: CGFloat, height: CGFloat, stacked: Bool) -> some View {
        let tileWidth = min(53, width * 0.35, height * (stacked ? 0.34 : 0.64))
        let labelWidth = stacked ? width - 8 : width * 0.55
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        return ZStack {
            if let result = table.result, let winner = result.winner {
                WinningHandReveal(table: table, result: result, winner: winner, name: name(of: winner),
                                  width: max(0, width - 8))
            } else if table.result != nil {
                Text("流局").font(.headline).foregroundStyle(board.accent)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("drawn-hand")
            } else if let latest {
                let claim = claimedBy(latest)
                let isGold = table.isGold(latest.tile)
                let owner = "\(name(of: latest.seat))打出"
                let tileName = latest.tile.kind.spokenName
                let detail = claim.map { "\(name(of: $0.seat)) · \($0.kind.label)" } ?? (isGold ? "金牌" : nil)
                let compact = !stacked && height < 54
                let singleLine = !stacked && height < 38
                let visibleTitle = if compact, let detail { "\(tileName) · \(detail)" } else { tileName }
                layout {
                    TileFace(kind: latest.tile.kind, gold: isGold)
                        .frame(width: tileWidth, height: tileWidth / TileFace.artworkAspectRatio)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                            if table.step == .claim, table.offeredTile?.id == latest.id {
                                onOfferedTileFrame(latest.id, frame)
                            }
                        }
                        .anchorPreference(key: TableAnchors.self, value: .bounds) { [.latestDiscard: $0] }
                        .shadow(color: .black.opacity(0.42), radius: 4, y: 3)
                        .opacity(latest.id == flyingDiscard || latest.id == flyingClaim ? 0 : claim == nil ? 1 : 0.55)
                        .accessibilityHidden(true)
                    VStack(alignment: stacked ? .center : .leading, spacing: compact ? 1 : 2) {
                        if !singleLine {
                            Text(owner).font(.caption2.weight(.semibold)).foregroundStyle(board.accent)
                        }
                        Text(singleLine ? "\(owner) · \(visibleTitle)" : visibleTitle)
                            .font(.system(compact ? .caption : .subheadline, design: .serif, weight: .bold))
                        if !compact, let detail { Text(detail).font(.caption2).foregroundStyle(board.muted) }
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
                Text("等待第一张出牌").font(.caption).foregroundStyle(board.muted)
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
