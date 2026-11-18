import FuzhouCore
import SwiftUI

struct LiveTable: View {
    let table: TableState
    let names: [Seat: String]
    let latest: TableDiscard?
    let drawingSeat: Seat?
    let drawStarted: Date?
    let drawingFromReserve: Bool
    let paused: Bool
    let size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let inset: CGFloat = 10
    private let gap: CGFloat = 6
    private let stripHeight: CGFloat = 24

    var body: some View {
        let width = max(0, size.width - inset * 2)
        let height = max(0, size.height - inset * 2)
        Group {
            if width >= 455, width > height {
                wideTable(width: width, height: height)
            } else {
                seatedTable(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .frame(width: size.width, height: size.height)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .foregroundStyle(TeaTheme.feltInk)
        .modifier(Felt(walnutRail: true))
        .overlayPreferenceValue(TableAnchors.self) { anchors in
            if let drawingSeat, let drawStarted, let wall = anchors[drawingFromReserve ? .reserve : .wall],
               let seat = anchors[.player(drawingSeat)], !reduceMotion {
                GeometryReader { geometry in
                    DrawPickup(started: drawStarted, wall: geometry[wall], player: geometry[seat])
                }
                .clipShape(RoundedRectangle(cornerRadius: TeaTheme.tableRailCorner, style: .circular))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table-surface")
    }

    private func seatedTable(width: CGFloat, height: CGFloat) -> some View {
        let endWidth = min(280, width * 0.77)
        let endHeight = min(54, max(38, height * 0.16))
        let sideWidth = min(108, width * 0.25)
        let middleWidth = max(0, width - 2 * (sideWidth + gap))
        let middleHeight = max(0, height - endHeight * 2 - stripHeight - gap * 3)
        let sideHeight = min(middleHeight, 118)

        return VStack(spacing: gap) {
            seatCard(table.viewer.advanced(2), width: endWidth, height: endHeight)
            HStack(spacing: gap) {
                seatCard(table.viewer.advanced(1), width: sideWidth, height: sideHeight, vertical: true)
                discardFocus(width: middleWidth, height: middleHeight, stacked: true)
                seatCard(table.viewer.advanced(3), width: sideWidth, height: sideHeight, vertical: true)
            }
            tableStrip(width: width)
            seatCard(table.viewer, width: endWidth, height: endHeight)
        }
    }

    private func wideTable(width: CGFloat, height: CGFloat) -> some View {
        let playersWidth = width * 0.56
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
            VStack(spacing: gap) {
                discardFocus(width: centerWidth, height: max(0, height - stripHeight - gap), stacked: false)
                tableStrip(width: centerWidth)
            }
        }
    }

    @ViewBuilder
    private func seatCard(_ seat: Seat, width: CGFloat, height: CGFloat, vertical: Bool = false) -> some View {
        if let player = table.players.first(where: { $0.seat == seat }) {
            let acting = !paused && table.step == .turn && table.current == seat
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
                    SeatBadge(seat: wind, highlighted: acting)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.caption.weight(.semibold))
                        Text(dealer ? "庄 · \(player.score)" : "\(player.score)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(acting ? TeaTheme.brass : TeaTheme.muted)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .frame(width: max(0, identityWidth), alignment: vertical ? .center : .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(wind.wind)风，\(name)，\(dealer ? "庄家，" : "")\(acting ? "当前回合，" : "")\(player.score)分")
                .accessibilityIdentifier("seat-score-\(seat.id)")

                meldSummary(player.melds, width: meldWidth, columns: vertical ? 2 : 3)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(name)的副露")
                    .accessibilityIdentifier("seat-melds-\(seat.id)")
                    .accessibilityHidden(player.melds.isEmpty)
            }
            .frame(width: width, height: height)
            .background(TeaTheme.feltDark.opacity(acting ? 0.94 : 0.72), in: shape)
            .overlay {
                shape.strokeBorder(acting ? TeaTheme.brass : TeaTheme.brassShade.opacity(0.35),
                                   lineWidth: acting ? 1.5 : 1)
            }
            .anchorPreference(key: TableAnchors.self, value: .bottom) { [.player(seat): $0] }
            .accessibilityElement(children: .contain)
        }
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
        let previous = Array((table.discardTimeline ?? []).filter { $0.id != latest?.id }.suffix(6))
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
                                .accessibilityLabel("\(name(of: discard.seat))打出的\(discard.tile.kind.spokenName)\(claimed ? "，已被取走" : "")")
                        } else {
                            Color.clear.accessibilityHidden(true)
                        }
                    }
                    .frame(width: tileWidth, height: min(stripHeight, tileWidth / TileFace.artworkAspectRatio))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("之前的弃牌，按出牌顺序")
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
                        if index < stacks { stack }
                        if index == pickup, drawingSeat != nil, !drawingFromReserve { pickupOutline }
                    }
                    .frame(width: 9, height: 13)
                    .anchorPreference(key: TableAnchors.self, value: .center) { index == pickup ? [.wall: $0] : [:] }
                }
            }
            ZStack {
                stack
                if drawingSeat != nil, drawingFromReserve { pickupOutline }
            }
            .frame(width: 9, height: 13)
            .anchorPreference(key: TableAnchors.self, value: .center) { [.reserve: $0] }
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
            if let latest {
                let claim = claimedBy(latest)
                layout {
                    TileFace(kind: latest.tile.kind, gold: table.isGold(latest.tile))
                        .frame(width: tileWidth, height: tileWidth / TileFace.artworkAspectRatio)
                        .shadow(color: .black.opacity(0.42), radius: 4, y: 3)
                        .accessibilityHidden(true)
                    VStack(alignment: stacked ? .center : .leading, spacing: 2) {
                        Text("\(name(of: latest.seat))打出").font(.caption2.weight(.semibold)).foregroundStyle(TeaTheme.brass)
                        Text(latest.tile.kind.spokenName).font(.system(.subheadline, design: .serif, weight: .bold))
                        Text(claim.map { "\(name(of: $0.seat)) · \($0.kind.label)" } ?? (table.isGold(latest.tile) ? "金牌" : " "))
                            .font(.caption2).foregroundStyle(TeaTheme.muted)
                            .accessibilityHidden(claim == nil && !table.isGold(latest.tile))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: max(0, labelWidth), alignment: stacked ? .center : .leading)
                }
                .accessibilityElement(children: .combine)
                .id(latest.id)
                .transition(.opacity)
            } else {
                Text("等待弃牌").font(.caption).foregroundStyle(TeaTheme.muted)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: width, height: height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: latest?.id)
        .accessibilityIdentifier("latest-discard")
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

    var body: some View {
        HStack(spacing: 2) {
            Text(meld.kind.label).font(.caption2).padding(.trailing, 1)
            ForEach(meld.tiles) { tile in
                TileFace(kind: tile.kind).frame(width: width, height: width * 1.34)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meld.kind.label)，\(meld.tiles.map { $0.kind.spokenName }.joined(separator: "、"))")
    }
}

private struct TableAnchors: PreferenceKey {
    enum Marker: Hashable { case wall, reserve, player(Seat) }
    static let defaultValue: [Marker: Anchor<CGPoint>] = [:]

    static func reduce(value: inout [Marker: Anchor<CGPoint>], nextValue: () -> [Marker: Anchor<CGPoint>]) {
        value.merge(nextValue()) { _, new in new }
    }
}
