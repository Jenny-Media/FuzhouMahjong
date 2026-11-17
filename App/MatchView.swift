import FuzhouCore
import SwiftUI
import UIKit

struct MatchView<Session: MatchSession>: View {
    let session: Session

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("practice.haptics.enabled") private var hapticsEnabled = true
    @AppStorage("table.sound.enabled") private var soundEnabled = true
    @AppStorage("table.sound.nearbyOwnMovesOnly") private var nearbyOwnMovesOnly = true
    @State private var selectedID: Tile.ID?
    @State private var showsHistory = false
    @State private var openingStage = OpeningDeal.Stage.shuffle(nil)
    @State private var openingAnimationRound: Int?
    @State private var audio = TableAudio()
    @State private var observedDiscard: TableDiscard?
    @State private var drawCue: DrawCue?
    @State private var drawingSeat: Seat?
    @State private var drawStarted: Date?
    @State private var arranging = false
    @State private var arrangementSelection: Tile.ID?
    @State private var handOrder: [Tile.ID]?
    @State private var rackFrame = CGRect.zero

    private var opening: Int? { session.openingRound }
    private var active: Bool { scenePhase == .active && !session.paused }

    var body: some View {
        Group {
            if let table = session.table {
                if let opening, opening == table.roundNumber {
                    OpeningDeal(viewer: table.viewer, dealer: table.dealer,
                                stage: openingAnimationRound == opening ? openingStage : .shuffle(nil),
                                reduceMotion: reduceMotion || !active) { finishOpening(opening) }
                } else if let result = table.result {
                    MatchResults(table: table, result: result, names: names,
                                 canAdvance: session.canAdvance && !session.paused) {
                        selectedID = nil
                        openingStage = .shuffle(nil)
                        session.nextHand()
                    }
                } else {
                    board(table)
                }
            }
        }
        .background(TeaTheme.canvas)
        .navigationTitle(session.table?.result == nil ? "牌桌" : "本局结算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if opening == nil, session.table?.result == nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(arranging ? "完成" : "理牌") {
                        arranging.toggle()
                        arrangementSelection = nil
                    }
                    .disabled(session.table?.hand.isEmpty != false)
                    .accessibilityIdentifier("rack-arrange")
                    Button("牌河") { showsHistory = true }
                }
            }
        }
        .sheet(isPresented: $showsHistory) {
            if let table = session.table { TableHistory(table: table, names: names) }
        }
        .task(id: OpeningRun(round: opening, active: active)) {
            guard let opening, active else { return }
            await performOpening(opening)
        }
        .task(id: TurnState(revision: session.revision, ready: active && opening == nil)) {
            guard active, opening == nil, session.computerHasMove else { return }
            let delay = session.table?.step == .turn ? Int.random(in: 1150...1420) : Int.random(in: 220...360)
            do { try await Task.sleep(for: .milliseconds(delay)) }
            catch { return }
            guard !Task.isCancelled, opening == nil, active else { return }
            session.advanceComputer()
        }
        .task(id: drawCue?.id) {
            drawingSeat = nil
            drawStarted = nil
            guard let drawCue else { return }
            if drawCue.afterContact {
                do { try await Task.sleep(for: .milliseconds(168)) }
                catch { return }
            }
            guard !Task.isCancelled, active, session.table?.current == drawCue.seat else { return }
            drawingSeat = drawCue.seat
            drawStarted = .now
            do {
                let contact = reduceMotion ? 0 : DrawPickup.contactDelay
                try await Task.sleep(for: .seconds(contact))
                guard !Task.isCancelled else { return }
                play(.draw, by: drawCue.seat)
                try await Task.sleep(for: .seconds(DrawPickup.duration - contact))
            } catch { return }
            drawingSeat = nil
            drawStarted = nil
        }
        .onChange(of: session.table) { before, after in
            guard let before, let after else { return }
            readTableChange(from: before, to: after)
        }
        .onChange(of: soundEnabled) { _, enabled in
            if !enabled { audio.stop() }
        }
        .onChange(of: active) { _, nowActive in
            if !nowActive {
                audio.stop()
                drawCue = nil
            }
        }
        .onDisappear { audio.stop() }
        .onChange(of: session.revision) { _, _ in
            if let selectedID, let table = session.table,
               !table.moves.contains(.discard(selectedID)), !table.moves.contains(.replaceFlower(selectedID)) {
                self.selectedID = nil
            }
        }
        .onChange(of: session.table?.roundNumber) { _, _ in resetArrangement() }
        .onChange(of: session.table?.result) { _, result in
            if result != nil { resetArrangement() }
        }
        .onChange(of: session.table?.hand) { _, hand in
            guard let hand else { return }
            if handOrder != nil { handOrder = orderedHand(hand).map(\.id) }
            if let arrangementSelection, !hand.contains(where: { $0.id == arrangementSelection }) {
                self.arrangementSelection = nil
            }
        }
    }

    private struct TurnState: Equatable { var revision: Int; var ready: Bool }
    private struct OpeningRun: Equatable { var round: Int?; var active: Bool }
    private struct DrawCue {
        let id = UUID()
        let seat: Seat
        let afterContact: Bool
        let fromReserve: Bool
    }

    private func performOpening(_ round: Int) async {
        openingAnimationRound = round
        openingStage = .shuffle(.now)
        play(.shuffle)
        do {
            if reduceMotion {
                try await Task.sleep(for: .milliseconds(650))
                openingStage = .settled
                play(.deal)
            } else {
                try await Task.sleep(for: .seconds(ShuffleMotion.duration))
                openingStage = .stacking
                try await Task.sleep(for: .milliseconds(330))
                let start = Date.now
                openingStage = .deal(start)
                let clock = ContinuousClock()
                let dealStart = clock.now
                let circuit = OpeningDeal.tileInterval * Double(Seat.allCases.count)
                for pass in 0..<FuzhouMatch.rackSize {
                    let arrival = OpeningDeal.flightDuration + Double(pass) * circuit
                    try await clock.sleep(until: dealStart.advanced(by: .seconds(arrival)))
                    play(.deal)
                }
            }
            try await Task.sleep(for: .milliseconds(280))
        } catch { return }
        guard !Task.isCancelled else { return }
        finishOpening(round)
    }

    private func finishOpening(_ round: Int) {
        audio.stop(.shuffle)
        session.finishOpening(round)
        if let table = session.table, table.step == .turn {
            drawCue = DrawCue(seat: table.current, afterContact: false,
                              fromReserve: table.lastDraw?.fromReserve == true)
        }
    }

    private func readTableChange(from before: TableState, to after: TableState) {
        guard active, opening == nil, before.roundNumber == after.roundNumber else {
            observedDiscard = nil
            drawCue = nil
            return
        }
        let pairs = zip(before.players, after.players)
        let discard = changedDiscard(from: before, to: after)
        if let discard { observedDiscard = discard }
        let meldingPlayer = pairs.first { $1.melds != $0.melds }?.1
        let meld = meldingPlayer?.melds.last
        let replacedFlower = pairs.contains { $1.flowerCount > $0.flowerCount }
        let contact = discard != nil || meld != nil
        if before.result == nil, let winner = after.result?.winner { play(.win, by: winner) }
        else if let meldingPlayer { play(.meld, by: meldingPlayer.seat) }
        else if let discard { play(.discard, by: discard.seat) }

        let legacyDraw = after.remaining < before.remaining || (after.drawn != nil && after.drawn != before.drawn) ||
            replacedFlower || meld.map { $0.kind != .chow && $0.kind != .pung } == true
        if after.step == .turn, let draw = after.lastDraw, draw != before.lastDraw {
            drawCue = DrawCue(seat: draw.seat, afterContact: contact, fromReserve: draw.fromReserve)
        } else if after.step == .turn, after.lastDraw == nil, legacyDraw {
            drawCue = DrawCue(seat: after.current, afterContact: contact, fromReserve: meld != nil)
        } else if before.current != after.current || before.step != after.step || contact {
            drawCue = nil
        }
    }

    private func changedDiscard(from before: TableState, to after: TableState) -> TableDiscard? {
        if let discard = after.discardTimeline?.last, discard.id != before.discardTimeline?.last?.id {
            return discard
        }
        // Older hosts still publish the public discards by player.
        let changed = zip(before.players, after.players).first { $1.discards.count > $0.discards.count }?.1
        guard let changed, let tile = changed.discards.last else { return nil }
        return TableDiscard(seat: changed.seat, tile: tile)
    }

    private func play(_ cue: TableAudio.Cue, by seat: Seat? = nil) {
        guard active, soundEnabled else { return }
        let isNearby = !session.players.isEmpty
        if isNearby, nearbyOwnMovesOnly {
            guard let seat, seat == session.table?.viewer else { return }
        }
        audio.play(cue, volume: isNearby ? 0.64 : 0.85)
    }

    private var names: [Seat: String] {
        Dictionary(uniqueKeysWithValues: session.players.map { ($0.seat, $0.name) })
    }

    private func board(_ table: TableState) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                header(table)
                GeometryReader { surface in
                    ScrollView {
                        LiveTable(table: table, names: names, latest: table.latestDiscard ?? observedDiscard,
                                  drawingSeat: drawingSeat, drawStarted: drawStarted,
                                  drawingFromReserve: drawCue?.fromReserve == true, paused: session.paused,
                                  minimumHeight: surface.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("table-scroll")
                }
                VStack(spacing: 6) {
                    if arranging { arrangementControls(table) }
                    else { actions(table) }
                    rack(table, availableWidth: max(0, geometry.size.width - TeaTheme.tableGutter * 2))
                }
            }
            .padding(.horizontal, TeaTheme.tableGutter)
            .padding(.vertical, 8)
        }
    }

    private func header(_ table: TableState) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(table.wind.wind)\(table.handNumber)局 · 连庄 \(table.continuation)")
                Label("余 \(table.remaining) 张", systemImage: "square.stack")
                    .monospacedDigit()
                    .font(.caption)
                    .accessibilityLabel("牌山剩余 \(table.remaining) 张")
            }
            Spacer(minLength: 0)
            if let gold = table.gold { goldIndicator(gold.kind) }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TeaTheme.muted)
    }

    private func goldIndicator(_ kind: TileKind) -> some View {
        let name = kind.suit.isBonus ? "花牌、季节牌" : kind.spokenName
        return HStack(spacing: 8) {
            TileFace(kind: kind, gold: true).frame(width: 32, height: 42).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("本局金牌").font(.caption)
                Text(name).font(.subheadline.weight(.bold)).foregroundStyle(TeaTheme.ink)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(TeaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("本局金牌，\(name)")
        .accessibilityIdentifier("gold-indicator")
    }

    private func activeTile(_ table: TableState) -> Tile.ID? {
        let ids = table.moves.compactMap {
            switch $0 { case .discard(let id), .replaceFlower(let id): id; default: nil }
        }
        if let selectedID, ids.contains(selectedID) { return selectedID }
        if let drawn = table.drawn, ids.contains(drawn.id) { return drawn.id }
        return ids.first
    }

    private func rack(_ table: TableState, availableWidth: CGFloat) -> some View {
        let maxColumns = max(1, Int(availableWidth / TeaTheme.hitTarget))
        let count = maxColumns >= 8 ? 8 : min(6, maxColumns)
        let columns = Array(repeating: GridItem(.flexible(minimum: TeaTheme.hitTarget), spacing: 0),
                            count: count)
        let tiles = orderedHand(table.hand)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                if arranging {
                    RackTile(tile: tile, isGold: table.isGold(tile), isSelected: tile.id == arrangementSelection,
                             canSelect: true, canDiscard: false, select: {
                        selectForArrangement(tile.id, at: index)
                    }, discard: {}, reposition: { point in
                        finishReorder(tile.id, at: point, columns: count, tileCount: tiles.count)
                    }, moveEarlier: index > 0 ? { moveInHand(tile.id, to: index - 1) } : nil,
                             moveLater: index + 1 < tiles.count ? { moveInHand(tile.id, to: index + 1) } : nil)
                } else {
                    tileButton(tile, table: table)
                }
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { rackFrame = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("手牌")
    }

    private func arrangementControls(_ table: TableState) -> some View {
        HStack(spacing: 8) {
            Text(arrangementSelection == nil ? "拖动手牌调整顺序" : "轻点目标位置")
                .font(.subheadline)
            Spacer(minLength: 0)
            if let drawn = table.drawn {
                TileFace(kind: drawn.kind, gold: table.isGold(drawn))
                    .frame(width: 26, height: 36)
                    .accessibilityLabel("本巡摸牌，\(drawn.kind.spokenName)")
            }
            Button("自动排序") {
                handOrder = nil
                arrangementSelection = nil
            }
            .buttonStyle(TeaButtonStyle(prominent: false))
            .disabled(handOrder == nil)
            .accessibilityIdentifier("rack-autosort")
        }
    }

    private func resetArrangement() {
        arranging = false
        arrangementSelection = nil
        handOrder = nil
    }

    private func orderedHand(_ hand: [Tile]) -> [Tile] {
        guard let handOrder else { return hand }
        let byID = Dictionary(uniqueKeysWithValues: hand.map { ($0.id, $0) })
        let placed = Set(handOrder)
        return handOrder.compactMap { byID[$0] } + hand.filter { !placed.contains($0.id) }
    }

    private func selectForArrangement(_ id: Tile.ID, at index: Int) {
        if let arrangementSelection, arrangementSelection != id {
            moveInHand(arrangementSelection, to: index)
        } else {
            arrangementSelection = arrangementSelection == nil ? id : nil
        }
    }

    private func finishReorder(_ id: Tile.ID, at point: CGPoint, columns: Int, tileCount: Int) {
        guard rackFrame.contains(point), tileCount > 0 else { return }
        let rows = (tileCount + columns - 1) / columns
        let column = Int((point.x - rackFrame.minX) / rackFrame.width * CGFloat(columns))
        let row = Int((point.y - rackFrame.minY) / rackFrame.height * CGFloat(rows))
        moveInHand(id, to: min(tileCount - 1, row * columns + column))
    }

    private func moveInHand(_ id: Tile.ID, to destination: Int) {
        guard arranging, let table = session.table else { return }
        var ids = orderedHand(table.hand).map(\.id)
        guard let source = ids.firstIndex(of: id), ids.indices.contains(destination) else {
            arrangementSelection = nil
            return
        }
        if source != destination {
            ids.remove(at: source)
            ids.insert(id, at: destination)
            handOrder = ids
            if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        }
        arrangementSelection = nil
    }

    private func tileButton(_ tile: Tile, table: TableState) -> some View {
        let canDiscard = active && table.moves.contains(.discard(tile.id))
        let canSelect = canDiscard || (active && table.moves.contains(.replaceFlower(tile.id)))
        return RackTile(tile: tile, isGold: table.isGold(tile), isSelected: tile.id == activeTile(table),
                        canSelect: canSelect, canDiscard: canDiscard, select: {
            guard selectedID != tile.id else { return }
            if reduceMotion { selectedID = tile.id }
            else { withAnimation(.easeOut(duration: 0.15)) { selectedID = tile.id } }
            if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        }, discard: {
            send(.discard(tile.id))
        })
    }

    private func actions(_ table: TableState) -> some View {
        let specials = table.moves.filter {
            switch $0 { case .win, .meld, .pass: true; default: false }
        }
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(status(table)).font(.headline)
                    if let id = activeTile(table),
                       let tile = (table.hand + [table.drawn].compactMap { $0 }).first(where: { $0.id == id }) {
                        Text(table.moves.contains(.discard(id)) ? "上滑出牌 · \(tile.kind.spokenName)" : "已选 \(tile.kind.spokenName)")
                            .font(.caption).foregroundStyle(TeaTheme.muted)
                    }
                }
                Spacer(minLength: 0)
                if let drawn = table.drawn {
                    tileButton(drawn, table: table)
                        .frame(width: TeaTheme.hitTarget)
                        .accessibilityHint("本巡摸牌")
                }
                if let id = activeTile(table) {
                    let isFlower = table.moves.contains(.replaceFlower(id))
                    Button(isFlower ? "补花" : "出牌") { send(isFlower ? .replaceFlower(id) : .discard(id)) }
                        .buttonStyle(TeaButtonStyle(prominent: !specials.contains(.win)))
                        .disabled(session.paused)
                        .accessibilityIdentifier("discard-action")
                }
            }
            if !specials.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { specialButtons(specials, table: table) }
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) { specialButtons(specials, table: table) }
                    }
                }
            }
        }
    }

    private func status(_ table: TableState) -> String {
        if session.paused { return "等待玩家重新连接" }
        if table.moves.contains(.win), table.step == .opening { return "可以抢金" }
        if table.step == .opening { return "等待抢金选择" }
        if table.step == .claim { return table.moves.isEmpty ? "等待牌友选择" : "可以响应弃牌" }
        if table.current == table.viewer { return "轮到你出牌" }
        let name = displayName(table.current, viewer: table.viewer, names: names)
        return drawingSeat == table.current ? "\(name)正在摸牌" : "\(name)正在选牌"
    }

    private func specialButtons(_ moves: [Move], table: TableState) -> some View {
        ForEach(moves, id: \.self) { move in
            Button(title(move, table: table)) { send(move) }
                .fixedSize(horizontal: true, vertical: false)
                .buttonStyle(TeaButtonStyle(prominent: move == .win))
                .disabled(session.paused)
        }
    }

    private func title(_ move: Move, table: TableState) -> String {
        switch move {
        case .win:
            switch table.step { case .opening: "抢金"; case .claim: "胡"; default: "自摸" }
        case .pass: "过"
        case .meld(let kind, let ids):
            if kind == .chow {
                "吃 \(table.hand.filter { ids.contains($0.id) }.map(\.kind.spokenName).joined(separator: "・"))"
            } else {
                kind.label
            }
        default: ""
        }
    }

    private func send(_ move: Move) {
        guard active, !arranging, opening == nil, session.table?.moves.contains(move) == true,
              session.submit(move) else { return }
        selectedID = nil
        guard hapticsEnabled else { return }
        if move == .win { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else if case .discard = move { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }
}

private struct TableHistory: View {
    var table: TableState
    var names: [Seat: String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(table.players) { player in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(table.wind(for: player.seat).wind) · \(displayName(player.seat, viewer: table.viewer, names: names))")
                                .font(.headline)
                            Text("花牌 \(player.flowerCount) · 积分 \(player.score)").font(.subheadline)
                            ForEach(player.melds) { meld in
                                HStack(spacing: 4) {
                                    Text(meld.kind.label).font(.caption)
                                    ForEach(meld.tiles) { tile in
                                        TileFace(kind: tile.kind).frame(width: 23, height: 30)
                                    }
                                }
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 25), spacing: 4)], spacing: 4) {
                                ForEach(player.discards) { tile in
                                    TileFace(kind: tile.kind, gold: table.isGold(tile)).frame(width: 24, height: 31)
                                }
                            }
                            Divider()
                        }
                    }
                }
                .padding(TeaTheme.gutter)
            }
            .navigationTitle("牌河与副露")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

func displayName(_ seat: Seat, viewer: Seat, names: [Seat: String]) -> String {
    if seat == viewer { return "你" }
    return names[seat] ?? "电脑\(["甲", "乙", "丙", "丁"][seat.id])"
}

extension MeldKind {
    var label: String {
        switch self { case .chow: "吃"; case .pung: "碰"; case .openKong: "明杠"; case .concealedKong: "暗杠"; case .addedKong: "加杠" }
    }
}
