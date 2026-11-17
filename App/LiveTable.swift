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
    let minimumHeight: CGFloat
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if compact {
                HStack(alignment: .top, spacing: 12) {
                    playerGrid
                    VStack(spacing: 6) {
                        discardFocus
                        HStack(spacing: 8) {
                            wallSources.fixedSize(horizontal: true, vertical: false)
                            previousDiscards
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    playerGrid
                    wallSources
                    discardFocus
                    previousDiscards
                }
            }
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
        .foregroundStyle(TeaTheme.feltInk)
        .modifier(Felt())
        .overlayPreferenceValue(TableAnchors.self) { anchors in
            if let drawingSeat, let drawStarted, let wall = anchors[drawingFromReserve ? .reserve : .wall],
               let seat = anchors[.player(drawingSeat)], !reduceMotion {
                GeometryReader { geometry in
                    DrawPickup(started: drawStarted, wall: geometry[wall], player: geometry[seat])
                }
                .clipShape(RoundedRectangle(cornerRadius: TeaTheme.tableCorner))
            }
        }
    }

    private var playerGrid: some View {
        let seats = (0..<Seat.allCases.count).map { table.viewer.advanced($0) }
        let count = typeSize.isAccessibilitySize ? 1 : 2
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6, alignment: .top), count: count)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(seats) { seat in
                if let player = table.players.first(where: { $0.seat == seat }) { playerCard(player) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("本桌玩家")
    }

    private func playerCard(_ player: TableState.Player) -> some View {
        let acting = !paused && table.step == .turn && table.current == player.seat
        let dealer = table.dealer == player.seat
        let name = name(of: player.seat)
        let drawLabel = acting ? drawStatus(for: player.seat) : nil
        return HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    if acting { Circle().fill(TeaTheme.brass).frame(width: 5, height: 5).accessibilityHidden(true) }
                    Text(name).font(.caption.weight(.semibold)).lineLimit(1)
                }
                Text(dealer ? "庄 · \(player.score)" : "\(player.score)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(acting ? TeaTheme.brass : TeaTheme.feltInk.opacity(0.84))
                    .lineLimit(1)
                if let drawLabel {
                    Text(drawLabel).font(.caption2.weight(.semibold)).foregroundStyle(TeaTheme.brass).lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name)，\(dealer ? "庄家，" : "")\(acting ? "当前回合，" : "")\(player.score)分\(drawLabel.map { "，\($0)" } ?? "")")
            Spacer(minLength: 1)
            if !player.melds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(player.melds) { meld in MeldTiles(meld: meld, width: 15) }
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(name)的副露")
                .accessibilityIdentifier("seat-melds-\(player.seat.id)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 44 : 49, alignment: .topLeading)
        .padding(.horizontal, 7)
        .padding(.vertical, compact ? 4 : 6)
        .background(TeaTheme.feltDark.opacity(acting ? 0.88 : 0.67), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(acting ? TeaTheme.brass : TeaTheme.feltInk.opacity(0.16), lineWidth: acting ? 1.5 : 1)
        }
        .anchorPreference(key: TableAnchors.self, value: .bottom) { [.player(player.seat): $0] }
        .accessibilityElement(children: .contain)
    }

    private func drawStatus(for seat: Seat) -> String? {
        if drawingSeat == seat { return drawingFromReserve ? "补牌中" : "摸牌中" }
        guard let draw = table.lastDraw, draw.seat == seat else { return nil }
        if draw.flowersReplaced > 0 { return "补花 \(draw.flowersReplaced)" }
        return draw.fromReserve ? "已补牌" : "已摸牌"
    }

    private var wallSources: some View {
        HStack(spacing: 12) {
            wallStrip
            reserveStack
            Spacer(minLength: 0)
        }
        .frame(minHeight: 31)
    }

    private var wallStrip: some View {
        let maximumStacks = 7
        let stacks = min(maximumStacks, max(0, (table.remaining + 8) / 9))
        let pickup = max(0, stacks - 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<maximumStacks, id: \.self) { index in
                    ZStack {
                        if index < stacks { stack }
                        if index == pickup, drawingSeat != nil, !drawingFromReserve { pickupOutline }
                    }
                    .frame(width: 11, height: 15)
                    .anchorPreference(key: TableAnchors.self, value: .center) { index == pickup ? [.wall: $0] : [:] }
                }
            }
            Text("牌山").font(.caption2)
        }
        .accessibilityHidden(true)
    }

    private var reserveStack: some View {
        VStack(spacing: 4) {
            ZStack {
                stack
                if drawingSeat != nil, drawingFromReserve { pickupOutline }
            }
            .frame(width: 11, height: 15)
            .anchorPreference(key: TableAnchors.self, value: .center) { [.reserve: $0] }
            Text("补牌").font(.caption2)
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

    private var discardFocus: some View {
        HStack(spacing: 15) {
            if let latest {
                TileFace(kind: latest.tile.kind, gold: table.isGold(latest.tile), selected: true)
                    .frame(width: 49, height: 66)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(name(of: latest.seat))打出")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TeaTheme.brass)
                    Text(latest.tile.kind.spokenName)
                        .font(.title3.weight(.semibold))
                    if table.isGold(latest.tile) {
                        Text("金牌").font(.caption)
                    }
                    if let claim = claimedBy(latest) {
                        Text("\(name(of: claim.seat)) · \(claim.kind.label)")
                            .font(.caption).foregroundStyle(TeaTheme.feltInk.opacity(0.84))
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("等待弃牌")
                    .font(.subheadline)
                    .foregroundStyle(TeaTheme.feltInk.opacity(0.84))
            }
        }
        .id(latest?.id)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: -3)))
        .frame(maxWidth: .infinity, minHeight: compact ? 72 : 100, maxHeight: .infinity)
        .background(TeaTheme.feltDark.opacity(0.71), in: RoundedRectangle(cornerRadius: TeaTheme.surfaceCorner))
        .overlay {
            RoundedRectangle(cornerRadius: TeaTheme.surfaceCorner)
                .strokeBorder(TeaTheme.feltInk.opacity(0.15), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: latest?.id)
        .accessibilityIdentifier("latest-discard")
    }

    private var previousDiscards: some View {
        let previous = (table.discardTimeline ?? []).filter { $0.id != latest?.id }.suffix(6)
        return HStack(alignment: .center, spacing: compact ? 3 : 5) {
            if !previous.isEmpty {
                Text("此前").font(.caption2).padding(.trailing, 2)
                ForEach(previous) { discard in
                    TileFace(kind: discard.tile.kind, gold: table.isGold(discard.tile))
                        .frame(width: compact ? 18 : 24, height: compact ? 25 : 31)
                        .opacity(claimedBy(discard) == nil ? 1 : 0.62)
                        .accessibilityLabel("\(name(of: discard.seat))打出的\(discard.tile.kind.spokenName)\(claimedBy(discard) == nil ? "" : "，已被取走")")
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 31)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("之前的弃牌，按出牌顺序")
        .accessibilityHidden(previous.isEmpty)
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
    }
}

private struct TableAnchors: PreferenceKey {
    enum Marker: Hashable { case wall, reserve, player(Seat) }
    static let defaultValue: [Marker: Anchor<CGPoint>] = [:]

    static func reduce(value: inout [Marker: Anchor<CGPoint>], nextValue: () -> [Marker: Anchor<CGPoint>]) {
        value.merge(nextValue()) { _, new in new }
    }
}
