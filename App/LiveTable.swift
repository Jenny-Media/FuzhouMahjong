import FuzhouCore
import SwiftUI

struct OpponentRackCounts {
    let total: Int
    let landed: Int

    init(_ player: TableState.Player, at table: TableState, pendingDraw: Seat?, reduceMotion: Bool) {
        total = max(0, table.concealedCount(for: player))
        let collecting = !reduceMotion && table.step == .turn && pendingDraw == player.seat
            && table.current == player.seat && player.seat != table.viewer
        landed = collecting ? max(0, total - 1) : total
    }
}

struct FlowerStripLayout {
    let tiles: ArraySlice<Tile>
    let hiddenCount: Int
    let labelWidth: CGFloat
    let countWidth: CGFloat
    let tileWidth: CGFloat
    let spacing: CGFloat

    init(_ player: TableState.Player, highlighted: Set<Tile.ID>, width: CGFloat, height: CGFloat) {
        let flowers = player.exposedFlowers ?? []
        let faceWidth = height * TileFace.artworkAspectRatio
        labelWidth = min(13, width * 0.24)
        let overflowWidth = min(player.flowerCount < 10 ? 12 : 17, width * 0.34)
        let tileSpace = width - labelWidth
        let capacity = Int(tileSpace / (faceWidth + 1))
        let compactCapacity = Int(max(0, tileSpace - overflowWidth - 1) / (faceWidth + 1))
        // Newly revealed flowers are appended to the row. Keep the full reveal visible while it is highlighted.
        let revealed = flowers.reversed().prefix { highlighted.contains($0.id) }.count
        let visibleCount = player.flowerCount <= capacity ? capacity : max(1, compactCapacity, revealed)
        tiles = flowers.suffix(visibleCount)
        hiddenCount = max(0, player.flowerCount - tiles.count)
        countWidth = hiddenCount > 0 ? overflowWidth : 0
        let available = max(0, tileSpace - countWidth)
        let gaps = CGFloat(tiles.count + (hiddenCount > 0 ? 1 : 0))
        spacing = min(1, available / (2 * max(1, gaps)))
        tileWidth = min(faceWidth, (available - gaps * spacing) / CGFloat(max(1, tiles.count)))
    }
}

struct LiveTable<Controls: View, DrawDock: View>: View {
    let table: TableState
    let names: [Seat: String]
    let latest: TableDiscard?
    let opening: OpeningDeal.Stage?
    let drawingFromReserve: Bool?
    var pendingDraw: Seat? = nil
    var highlightedFlowers: Set<Tile.ID> = []
    let paused: Bool
    let size: CGSize
    let showsDrawDock: Bool
    var showsInlineResultActions = true
    let flyingDiscard: Tile.ID?
    let flyingClaim: Tile.ID?
    @Binding var inspectedSeat: Seat?
    let onOfferedTileFrame: (Tile.ID, CGRect) -> Void
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let drawDock: () -> DrawDock

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardStyle) private var board
    @Environment(\.tileMaterial) private var tileMaterial


    private let inset: CGFloat = 10
    private let gap: CGFloat = 6
    private let stripHeight: CGFloat = 24
    private var showsFlowers: Bool { opening?.showsFlowers ?? true }

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
        .transformAnchorPreference(key: TableAnchors.self, value: .bounds) {
            if opening != nil { $0[.felt] = $1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table-surface")
        .onChange(of: table.roundNumber) { inspectedSeat = nil }
        .sheet(item: $inspectedSeat) { seat in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let player = table.players.first(where: { $0.seat == seat }) {
                            Text("\(table.wind(for: seat).wind)风 · \(player.score)分")
                                .font(.subheadline).foregroundStyle(TeaTheme.muted)
                            if showsFlowers, player.flowerCount > 0 {
                                Text("花牌 \(player.flowerCount) 张").font(.headline)
                                if let flowers = player.exposedFlowers, !flowers.isEmpty {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 4)], spacing: 4) {
                                        ForEach(flowers) { tile in
                                            TileFace(kind: tile.kind).frame(width: 36, height: 50)
                                                .accessibilityElement(children: .ignore)
                                                .accessibilityLabel(tile.kind.spokenName)
                                        }
                                    }
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier("inspected-flowers-\(seat.id)")
                                }
                            }
                            if player.melds.isEmpty, !showsFlowers || player.flowerCount == 0 {
                                Text("还没有亮出的牌")
                            }
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
            playingArea(width: width, height: middleHeight) { focusHeight in
                let sideHeight = min(focusHeight, 118)
                HStack(spacing: gap) {
                    seatCard(table.viewer.advanced(1), width: sideWidth, height: sideHeight, vertical: true)
                    discardFocus(width: middleWidth, height: focusHeight, stacked: true)
                    seatCard(table.viewer.advanced(3), width: sideWidth, height: sideHeight, vertical: true)
                }
            }
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
            playingArea(width: centerWidth, height: height) { focusHeight in
                discardFocus(width: centerWidth, height: focusHeight, stacked: false)
            }
        }
    }

    private func playingArea<Focus: View>(width: CGFloat, height: CGFloat,
                                          @ViewBuilder focus: (CGFloat) -> Focus) -> some View {
        // Reserve room for a confirmation row and the action buttons on every turn.
        let reservesControls = table.result == nil || showsInlineResultActions
        let controlsHeight = reservesControls ? min(height, TeaTheme.hitTarget + 48 + 4 + 12) : 0
        return VStack(spacing: 0) {
            focus(height - controlsHeight)
            if reservesControls {
                ZStack(alignment: .bottom) {
                    Color.clear.allowsHitTesting(false).accessibilityHidden(true)
                    controls()
                }
                .frame(height: controlsHeight)
            }
        }
        .frame(width: width, height: height)
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
                            if !player.melds.isEmpty || (showsFlowers && player.flowerCount > 0) {
                                Image(systemName: "magnifyingglass")
                            }
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

                let counts = OpponentRackCounts(player, at: table, pendingDraw: pendingDraw, reduceMotion: reduceMotion)
                let rackHeight = max(1, vertical ? height - 40 : height - 6)
                let hasFlowers = showsFlowers && player.flowerCount > 0
                let flowerHeight = hasFlowers ? min(19, rackHeight * 0.44) : 0
                let groupHeight = max(0, rackHeight - (hasFlowers ? flowerHeight + 2 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        if player.melds.isEmpty {
                            if seat != table.viewer, !won {
                                opponentRack(player, counts: counts)
                            }
                        } else {
                            let showsBacks = seat != table.viewer && !won && counts.total > 0
                            let backsHeight = min(8, groupHeight * 0.35)
                            if showsBacks {
                                smallRack(count: counts.landed, width: meldWidth)
                                    .frame(height: backsHeight)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("手牌 \(counts.total) 张")
                                    .accessibilityIdentifier("concealed-rack-\(seat.id)")
                            }
                            meldSummary(player.melds, width: meldWidth, height: groupHeight - (showsBacks ? backsHeight + 2 : 0))
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("\(name)亮出的牌组")
                                .accessibilityIdentifier("seat-melds-\(seat.id)")
                        }
                    }
                    .frame(width: meldWidth, height: groupHeight)
                    .transformAnchorPreference(key: TableAnchors.self, value: .bounds) { $0[.player(seat)] = $1 }
                    if hasFlowers { flowerStrip(player, width: meldWidth, height: flowerHeight) }
                }
                .frame(width: meldWidth, height: rackHeight)
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
            .transformAnchorPreference(key: TableAnchors.self, value: .bounds) {
                if opening != nil { $0[.seatCard(seat)] = $1 }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func flowerStrip(_ player: TableState.Player, width: CGFloat, height: CGFloat) -> some View {
        let layout = FlowerStripLayout(player, highlighted: highlightedFlowers, width: width, height: height)
        return HStack(spacing: layout.spacing) {
            Text("花").frame(width: layout.labelWidth)
            ForEach(layout.tiles) { flower in
                TileFace(kind: flower.kind)
                    .frame(width: layout.tileWidth, height: layout.tileWidth / TileFace.artworkAspectRatio)
                    .overlay {
                        if highlightedFlowers.contains(flower.id) {
                            RoundedRectangle(cornerRadius: 2).strokeBorder(board.accent, lineWidth: 1.5)
                        }
                    }
            }
            if layout.hiddenCount > 0 {
                Text(layout.tiles.isEmpty ? "\(layout.hiddenCount)" : "+\(layout.hiddenCount)")
                    .frame(width: layout.countWidth)
            }
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(board.ink)
        .frame(width: width, height: height, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(of: player.seat))，花牌 \(player.flowerCount) 张\(layout.tiles.isEmpty ? "" : "，" + layout.tiles.map { $0.kind.spokenName }.joined(separator: "、"))")
        .accessibilityIdentifier("seat-flowers-\(player.seat.id)")
    }

    private func smallRack(count: Int, width: CGFloat) -> some View {
        Canvas { context, size in
            let back = context.resolve(Image(decorative: tileMaterial.backArtwork))
            let tileWidth = min(size.height / 1.4, width / CGFloat(max(count, 1)))
            for index in 0..<count {
                OpeningDeal.drawBack(back, in: context,
                                     at: CGPoint(x: (CGFloat(index) + 0.5) * tileWidth, y: size.height / 2),
                                     width: tileWidth)
            }
        }
    }

    private func opponentRack(_ player: TableState.Player, counts: OpponentRackCounts) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: opening?.isDealing != true)) { time in
            let landed = opening?.landed(for: player.seat, dealer: table.dealer, at: time.date) ?? counts.landed
            Canvas { context, size in
                let back = context.resolve(Image(decorative: tileMaterial.backArtwork))
                for index in 0..<min(FuzhouMatch.rackSize, landed) {
                    let slot = OpeningDeal.opponentSlot(index, in: CGRect(origin: .zero, size: size))
                    OpeningDeal.drawBack(back, in: context, at: slot.center, width: slot.width)
                }
                let extraLanded = opening.map {
                    player.seat == table.dealer && table.lastDraw?.isOpeningDeal == true && $0.dealerTileLanded(at: time.date)
                } ?? (counts.landed > FuzhouMatch.rackSize)
                if extraLanded {
                    let extra = OpeningDeal.opponentDealerSlot(in: CGRect(origin: .zero, size: size))
                    OpeningDeal.drawBack(back, in: context, at: extra.center, width: extra.width)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("手牌 \(counts.total) 张")
        .accessibilityIdentifier("concealed-rack-\(player.seat.id)")
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
                let claimDetail = claim.map { "\(name(of: $0.seat)) · \($0.kind.label)" }
                let detail = claimDetail ?? (isGold ? "金牌" : nil)
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
                        HStack(spacing: 4) {
                            Text(singleLine ? "\(owner) · \(visibleTitle)" : visibleTitle)
                                .font(.system(compact ? .caption : .subheadline, design: .serif, weight: .bold))
                            if isGold && !compact {
                                Text("金牌")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(TeaTheme.color(0x292115))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(TeaTheme.modernTileGoldBadge, in: RoundedRectangle(cornerRadius: 3))
                                    .fixedSize()
                            }
                        }
                        if !compact, let claimDetail { Text(claimDetail).font(.caption2).foregroundStyle(board.muted) }
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
