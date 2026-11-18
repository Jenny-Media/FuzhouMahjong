import FuzhouAccess
import FuzhouCore
import SwiftUI
import UIKit

struct MatchView<Session: MatchSession>: View {
    let session: Session
    @Environment(GameAccess.self) private var access
    @State private var purchaseReason: AccessReason?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var primaryControlWidth = 80.0
    @AppStorage("practice.haptics.enabled") private var hapticsEnabled = true
    @AppStorage("table.sound.enabled") private var soundEnabled = true
    @AppStorage("table.sound.nearbyOwnMovesOnly") private var nearbyOwnMovesOnly = true
    @State private var selectedID: Tile.ID?
    @State private var showsHistory = false
    @State private var guideLesson: RuleLesson?
    @State private var showsScorecard = false
    @State private var openingStage = OpeningDeal.Stage.shuffle(nil)
    @State private var openingAnimationRound: Int?
    @State private var audio = TableAudio()
    @State private var observedDiscard: TableDiscard?
    @State private var drawCue: DrawCue?
    @State private var drawFlight: DrawPickup.Flight?
    @State private var arranging = false
    @State private var arrangementSelection: Tile.ID?
    @State private var rackFrame = CGRect.zero
    @State private var goldDiscard: GoldDiscard?

    private var opening: Int? { session.openingRound }
    private var active: Bool { scenePhase == .active && !session.paused }
    private var dealStage: OpeningDeal.Stage? {
        guard let opening else { return nil }
        return openingAnimationRound == opening ? openingStage : .shuffle(nil)
    }

    var body: some View {
        Group {
            if let table = session.table {
                board(table).accessibilityHidden(showsScorecard)
            }
        }
        .teaBackdrop()
        .navigationTitle("牌桌")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { guideLesson = contextualLesson } label: {
                    Label("玩法", systemImage: "questionmark.circle").labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("table-rules")
            }
            if opening == nil, session.table?.result == nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(arranging ? "完成" : "理牌", systemImage: arranging ? "checkmark" : "hand.draw") {
                        arranging.toggle()
                        arrangementSelection = nil
                    }
                    .disabled(session.table?.hand.isEmpty != false)
                    .accessibilityIdentifier("rack-arrange")
                    .accessibilityHint(arranging ? "返回出牌" : "拖动手牌调整顺序")
                    Button("牌河", systemImage: "square.grid.3x3") { showsHistory = true }
                }
            }
        }
        .fullScreenCover(isPresented: $showsScorecard) { scorecard }
        .sheet(isPresented: $showsHistory) {
            if let table = session.table { TableHistory(table: table, names: names) }
        }
        .sheet(item: $guideLesson) { lesson in
            NavigationStack { RuleGuide(startingAt: lesson, showsCloseButton: true) }
        }
        .alert("打出金牌？", isPresented: Binding(get: { goldDiscard != nil }, set: { if !$0 { goldDiscard = nil } }),
               presenting: goldDiscard) { confirmation in
            Button("取消", role: .cancel) { goldDiscard = nil }
            Button("打出金牌", role: .destructive) {
                if session.revision == confirmation.revision { commit(.discard(confirmation.tile.id)) }
            }
            .accessibilityIdentifier("confirm-gold-discard")
        } message: { confirmation in
            Text(confirmation.alreadyRestricted
                 ? "\(confirmation.tile.kind.spokenName)是金牌。打出后本局仍只能自摸。"
                 : "\(confirmation.tile.kind.spokenName)是金牌。打出金牌后，本局只能自摸。")
        }
        .task(id: OpeningRun(round: opening, active: active && !showsScorecard, reduceMotion: reduceMotion)) {
            guard let opening, active, !showsScorecard else { return }
            await performOpening(opening)
        }
        .task(id: TurnState(revision: session.revision, ready: active && opening == nil)) {
            guard !session.managesComputerTurns, active, opening == nil, session.computerHasMove else { return }
            let delay = session.table?.step == .turn ? Int.random(in: 1150...1420) : Int.random(in: 220...360)
            do { try await Task.sleep(for: .milliseconds(delay)) }
            catch { return }
            guard !Task.isCancelled, opening == nil, active else { return }
            session.advanceComputer()
        }
        .task(id: drawCue?.id) {
            drawFlight = nil
            guard let drawCue else { return }
            await performDraw(drawCue)
        }
        .onChange(of: session.table) { before, after in
            guard let before, let after else { return }
            readTableChange(from: before, to: after)
        }
        .onChange(of: soundEnabled) { _, enabled in
            if !enabled { audio.stop() }
        }
        .onChange(of: opening) { _, round in
            if round == nil {
                audio.stop(.shuffle)
                audio.stop(.deal)
                openingAnimationRound = nil
            }
        }
        .onChange(of: active) { _, nowActive in
            if !nowActive {
                audio.stop()
                drawCue = nil
                goldDiscard = nil
                if let opening { finishOpening(opening) }
            }
        }
        .onDisappear {
            audio.stop()
            if let opening { finishOpening(opening) }
        }
        .onChange(of: session.revision) { _, _ in
            goldDiscard = nil
            if let selectedID, let table = session.table,
               !table.moves.contains(.discard(selectedID)), !table.moves.contains(.replaceFlower(selectedID)) {
                self.selectedID = nil
            }
        }
        .onChange(of: session.table?.roundNumber) { _, _ in
            closeScorecardForNewHand()
            resetArrangement()
        }
        .onChange(of: session.table?.result) { before, result in
            if result == nil { closeScorecardForNewHand() }
            else {
                resetArrangement()
                if before == nil, UIAccessibility.isVoiceOverRunning, let table = session.table {
                    AccessibilityNotification.Announcement(status(table)).post()
                }
            }
        }
        .onChange(of: session.table?.hand) { _, hand in
            guard let hand else { return }
            if session.rackOrder != nil {
                let order = orderedHand(hand).map(\.id)
                if order != session.rackOrder { session.rackOrder = order }
            }
            if let arrangementSelection, !hand.contains(where: { $0.id == arrangementSelection }) {
                self.arrangementSelection = nil
            }
        }
    }

    private var scorecard: some View {
        NavigationStack {
            Group {
                if let table = session.table, let result = table.result {
                    MatchResults(table: table, result: result, names: names,
                                 canAdvance: session.canAdvance && !session.paused,
                                 advanceTitle: advanceTitle,
                                 advanceDetail: session.players.isEmpty ? access.soloAllowanceText : nil,
                                 returnToTable: { showsScorecard = false }, next: nextHand)
                }
            }
            .teaBackdrop()
            .navigationTitle("本局结算")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $purchaseReason) { PurchaseSheet(reason: $0) }
        }
    }

    private func closeScorecardForNewHand() {
        guard showsScorecard else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showsScorecard = false }
    }

    private var advanceTitle: String? {
        if session.players.isEmpty { return access.canBeginSoloHand ? nil : "解锁完整版 · 继续单机" }
        return access.canHost ? nil : "解锁完整版 · 继续做房主"
    }

    private func nextHand() {
        access.refreshClock()
        if session.players.isEmpty, !access.canBeginSoloHand { purchaseReason = .solo; return }
        if !session.players.isEmpty, !access.authorizeHosting() { purchaseReason = .hosting; return }
        selectedID = nil
        openingAnimationRound = nil
        session.nextHand()
    }

    private struct TurnState: Equatable { var revision: Int; var ready: Bool }
    private var contextualLesson: RuleLesson {
        guard let table = session.table else { return .turn }
        if table.step == .opening { return .gold }
        if table.result != nil || table.moves.contains(.win) { return .winning }
        if table.step == .claim || table.moves.contains(where: {
            if case .meld = $0 { true } else { false }
        }) { return .claims }
        if table.viewerMustSelfDraw { return .gold }
        if let id = activeTile(table),
           let tile = (table.hand + [table.drawn].compactMap { $0 }).first(where: { $0.id == id }),
           table.isGold(tile) { return .gold }
        return .turn
    }
    private struct OpeningRun: Equatable { var round: Int?; var active: Bool; var reduceMotion: Bool }
    private struct GoldDiscard {
        let tile: Tile
        let revision: Int
        let alreadyRestricted: Bool
    }
    private struct DrawCue {
        let id = UUID()
        let seat: Seat
        let afterContact: Bool
        let fromReserve: Bool
        let replacesFlowers: Bool
    }

    private func performOpening(_ round: Int) async {
        openingAnimationRound = round
        openingStage = .shuffle(reduceMotion ? nil : .now)
        play(.shuffle)
        do {
            if reduceMotion {
                try await Task.sleep(for: .milliseconds(650))
                openingStage = .settled
                play(.deal)
            } else {
                try await Task.sleep(for: .seconds(ShuffleMotion.duration))
                openingStage = .stacking(.now)
                try await Task.sleep(for: .seconds(OpeningDeal.stackingDuration))
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
        finishOpening(round, animateDraw: true)
    }

    private func finishOpening(_ round: Int, animateDraw: Bool = false) {
        guard opening == round else { return }
        audio.stop(.shuffle)
        audio.stop(.deal)
        openingAnimationRound = nil
        session.finishOpening(round)
        if animateDraw, let table = session.table, table.step == .turn {
            drawCue = DrawCue(seat: table.current, afterContact: false,
                              fromReserve: table.lastDraw?.fromReserve == true,
                              replacesFlowers: (table.lastDraw?.flowersReplaced ?? 0) > 0)
        }
    }

    private func performDraw(_ cue: DrawCue) async {
        defer {
            if drawCue?.id == cue.id {
                drawFlight = nil
                drawCue = nil
            }
        }
        do {
            if cue.afterContact { try await Task.sleep(for: .milliseconds(168)) }
            guard !Task.isCancelled, active, session.table?.current == cue.seat else { return }
            if reduceMotion {
                play(.draw, by: cue.seat)
                return
            }
            if !cue.fromReserve, cue.replacesFlowers {
                drawFlight = .init(fromReserve: false, duration: DrawPickup.flowerDuration)
                try await Task.sleep(for: .seconds(DrawPickup.flowerDuration))
            }
            drawFlight = .init(fromReserve: cue.fromReserve || cue.replacesFlowers, duration: DrawPickup.duration)
            try await Task.sleep(for: .seconds(DrawPickup.contactDelay))
            play(.draw, by: cue.seat)
            try await Task.sleep(for: .seconds(DrawPickup.duration - DrawPickup.contactDelay))
        } catch { return }
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
            drawCue = DrawCue(seat: draw.seat, afterContact: contact, fromReserve: draw.fromReserve,
                              replacesFlowers: draw.flowersReplaced > 0)
        } else if after.step == .turn, after.lastDraw == nil, legacyDraw {
            drawCue = DrawCue(seat: after.current, afterContact: contact, fromReserve: meld != nil,
                              replacesFlowers: replacedFlower)
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
            let divisions = FoldRegions.divisions(in: geometry)
            Group {
                #if canImport(SwiftUI, _version: 8.0.85)
                if #available(iOS 27.1, *), !divisions.isEmpty {
                    ArrangementView {
                        VStack(spacing: 6) {
                            header(table)
                            tableSurface(table)
                        }
                        .padding(TeaTheme.tableGutter)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("table-region")
                    } secondary: {
                        GeometryReader { panel in
                            handPanel(table, width: panel.size.width, singleRow: panel.size.width >= 600)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                        .padding(TeaTheme.tableGutter)
                    }
                    .arrangementViewStyle(.split)
                } else {
                    flatBoard(table, size: geometry.size)
                }
                #else
                flatBoard(table, size: geometry.size)
                #endif
            }
            .overlayPreferenceValue(TableAnchors.self) { anchors in
                if !reduceMotion, dealStage != nil || drawFlight != nil {
                    GeometryReader { overlay in
                        tableMotion(table, anchors: anchors.mapValues { overlay[$0] })
                            .mask {
                                Path { path in
                                    path.addRect(CGRect(origin: .zero, size: overlay.size))
                                    path.addRects(divisions)
                                }
                                .fill(style: FillStyle(eoFill: true))
                            }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder
    private func tableMotion(_ table: TableState, anchors: [TableAnchors.Marker: CGRect]) -> some View {
        if let dealStage {
            OpeningDeal(viewer: table.viewer, dealer: table.dealer, stage: dealStage, anchors: anchors)
        } else if let drawFlight, let seat = drawCue?.seat,
                  let source = anchors[drawFlight.fromReserve ? .reserve : .wall],
                  let destination = anchors[seat == table.viewer ? .drawn : .player(seat)] {
            DrawPickup(flight: drawFlight, source: source, destination: destination, isLocal: seat == table.viewer)
        }
    }

    private func flatBoard(_ table: TableState, size: CGSize) -> some View {
        let landscape = size.width > size.height
        let singleRow = landscape || size.width >= 600
        return VStack(spacing: 6) {
            if !landscape { header(table) }
            tableSurface(table)
            handPanel(table, width: max(0, size.width - TeaTheme.tableGutter * 2),
                      singleRow: singleRow, includesHeader: landscape)
        }
        .padding(.horizontal, TeaTheme.tableGutter)
        .padding(.vertical, 4)
    }

    private func tableSurface(_ table: TableState) -> some View {
        GeometryReader { surface in
            LiveTable(table: table, names: names, latest: table.latestDiscard ?? observedDiscard,
                      opening: dealStage, drawingFromReserve: drawFlight?.fromReserve,
                      paused: session.paused, size: surface.size)
        }
    }

    private func handPanel(_ table: TableState, width: CGFloat, singleRow: Bool, includesHeader: Bool = false) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if includesHeader { header(table) }
                HStack(spacing: 4) {
                    if !singleRow { drawSlot(table.drawn, table: table) }
                    Spacer(minLength: 0)
                    primaryControls(table)
                }
                .frame(width: includesHeader ? 240 : nil)
                .frame(minHeight: TeaTheme.hitTarget)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("table-actions")
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            rack(table, availableWidth: width, landscape: singleRow)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hand-panel")
    }

    @ViewBuilder
    private func primaryControls(_ table: TableState) -> some View {
        if let opening {
            Button { finishOpening(opening) } label: { tableControlLabel("跳过动画", primary: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("skip-opening")
        } else if table.result != nil {
            Button { showsScorecard = true } label: {
                tableControlLabel("查看结算", prominent: true, primary: true)
            }
                .buttonStyle(.plain)
                .accessibilityIdentifier("view-scorecard")
        } else if arranging {
            arrangementControls
        } else {
            actions(table)
        }
    }

    private func header(_ table: TableState) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("\(table.wind.wind)\(table.handNumber)局 · 连庄 \(table.continuation)")
                        .foregroundStyle(TeaTheme.ink)
                    Text("余 \(table.remaining) 张")
                        .accessibilityLabel("牌山剩余 \(table.remaining) 张")
                }
                .font(.caption.monospacedDigit())
                .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Text(status(table))
                        .foregroundStyle(!session.paused && !table.moves.isEmpty ? TeaTheme.brass : TeaTheme.ink)
                        .layoutPriority(table.viewerMustSelfDraw ? 0 : 1)
                        .accessibilityIdentifier("table-status")
                        .opacity(table.result == nil ? 1 : 0)
                        .accessibilityHidden(table.result != nil)
                    if table.viewerMustSelfDraw {
                        Text("本局只能自摸").foregroundStyle(TeaTheme.loss).layoutPriority(1)
                            .opacity(table.result == nil ? 1 : 0)
                            .accessibilityHidden(table.result != nil)
                    }
                }
                .font(.caption.weight(.semibold))
                .minimumScaleFactor(0.7)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let gold = table.gold {
                let hidden = opening != nil || gold.id == table.result?.winningTile?.id
                Button { guideLesson = .gold } label: { goldIndicator(gold.kind) }
                    .buttonStyle(.plain)
                    .opacity(hidden ? 0 : 1)
                    .allowsHitTesting(!hidden)
                    .accessibilityHidden(hidden)
                    .accessibilityHint("查看金牌玩法")
                    .accessibilityIdentifier("gold-rules")
            }
        }
        .frame(minHeight: TeaTheme.hitTarget)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundStyle(TeaTheme.muted)
    }

    private func goldIndicator(_ kind: TileKind) -> some View {
        let name = kind.suit.isBonus ? "花牌、季节牌" : kind.spokenName
        return HStack(spacing: 5) {
            TileFace(kind: kind, gold: true).frame(width: 23, height: 30).accessibilityHidden(true)
            Text("金牌").font(.caption.weight(.semibold)).foregroundStyle(TeaTheme.brass)
        }
        .padding(.horizontal, 7)
        .frame(minHeight: TeaTheme.hitTarget)
        .teaPanel(corner: 11, emphasized: true)
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

    private func rack(_ table: TableState, availableWidth: CGFloat, landscape: Bool) -> some View {
        let tiles = table.result?.winner == table.viewer ? [] : orderedHand(table.hand)
        let count = landscape ? FuzhouMatch.rackSize : FuzhouMatch.rackSize / 2
        let slotCount = landscape ? count + 1 : count
        let rim: CGFloat = 6
        let cellWidth = min(46, max(0, availableWidth - rim * 2) / CGFloat(slotCount))
        let cellHeight = max(TeaTheme.hitTarget, RackTile.faceSize(for: cellWidth).height)
        let rackHeight = landscape ? cellHeight : cellHeight * 2 + 4
        let columns = Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: count)
        return HStack(alignment: .bottom, spacing: 0) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: dealStage?.isDealing != true)) { time in
                let landed = dealStage?.landed(for: table.viewer, dealer: table.dealer, at: time.date) ?? tiles.count
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                        Group {
                            if arranging {
                                RackTile(tile: tile, isGold: table.isGold(tile), isSelected: tile.id == arrangementSelection,
                                         canSelect: true, canDiscard: false, rackCellWidth: cellWidth, select: {
                                    selectForArrangement(tile.id, at: index)
                                }, discard: {}, reposition: { point in
                                    finishReorder(tile.id, at: point, columns: count, tileCount: tiles.count)
                                }, moveEarlier: index > 0 ? { moveInHand(tile.id, to: index - 1) } : nil,
                                         moveLater: index + 1 < tiles.count ? { moveInHand(tile.id, to: index + 1) } : nil)
                            } else {
                                tileButton(tile, table: table, rackCellWidth: cellWidth)
                            }
                        }
                        .opacity(index < landed ? 1 : 0)
                        .anchorPreference(key: TableAnchors.self, value: .bounds) { [.rack(index): $0] }
                    }
                }
            }
            .frame(width: cellWidth * CGFloat(count), height: rackHeight, alignment: .top)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { rackFrame = $0 }
            .accessibilityHidden(opening != nil)

            if landscape {
                drawSlot(table.drawn, table: table, rackCellWidth: cellWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, rim)
        .padding(.vertical, 5)
        .background(TeaTheme.railFinish, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(TeaTheme.brassShade.opacity(0.55))
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("手牌")
        .accessibilityIdentifier("table-rack")
    }

    private func drawSlot(_ tile: Tile?, table: TableState, rackCellWidth: CGFloat? = nil) -> some View {
        let cellWidth = rackCellWidth ?? TeaTheme.hitTarget
        let cellHeight = max(TeaTheme.hitTarget, RackTile.faceSize(for: rackCellWidth).height)
        let visible = tile != nil && opening == nil && !localDrawInFlight(table)
        return VStack(spacing: 2) {
            Text("摸牌")
                .font(.caption2.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(TeaTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .opacity(visible ? 1 : 0)
                .accessibilityHidden(true)
            Group {
                if let tile {
                    tileButton(tile, table: table, rackCellWidth: rackCellWidth, isDrawn: true)
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(width: cellWidth, height: cellHeight)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(!visible)
            .anchorPreference(key: TableAnchors.self, value: .bounds) { [.drawn: $0] }
        }
        .frame(width: cellWidth)
    }

    private var arrangementControls: some View {
        Button {
            session.rackOrder = nil
            arrangementSelection = nil
        } label: {
            tableControlLabel("自动排序")
        }
        .buttonStyle(.plain)
        .disabled(session.rackOrder == nil)
        .opacity(session.rackOrder == nil ? 0.5 : 1)
        .accessibilityIdentifier("rack-autosort")
    }

    private func resetArrangement() {
        arranging = false
        arrangementSelection = nil
    }

    private func orderedHand(_ hand: [Tile]) -> [Tile] {
        guard let order = session.rackOrder else { return hand }
        var remaining = Dictionary(uniqueKeysWithValues: hand.map { ($0.id, $0) })
        return order.compactMap { remaining.removeValue(forKey: $0) } + hand.filter { remaining[$0.id] != nil }
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
        let rows = FuzhouMatch.rackSize / columns
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
            session.rackOrder = ids
            if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        }
        arrangementSelection = nil
    }

    private func tileButton(_ tile: Tile, table: TableState, rackCellWidth: CGFloat? = nil,
                            isDrawn: Bool = false) -> some View {
        let playable = active && !arranging && opening == nil && !localDrawInFlight(table)
        let canDiscard = playable && table.moves.contains(.discard(tile.id))
        let canSelect = canDiscard || (playable && table.moves.contains(.replaceFlower(tile.id)))
        return RackTile(tile: tile, isGold: table.isGold(tile), isSelected: playable && tile.id == activeTile(table),
                        isDrawn: isDrawn,
                        canSelect: canSelect, canDiscard: canDiscard, rackCellWidth: rackCellWidth, select: {
            guard selectedID != tile.id else { return }
            if reduceMotion { selectedID = tile.id }
            else { withAnimation(.easeOut(duration: 0.15)) { selectedID = tile.id } }
            if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        }, discard: {
            send(.discard(tile.id))
        })
    }

    private func actions(_ table: TableState) -> some View {
        let selected = activeTile(table)
        let replacesFlower = selected.map { table.moves.contains(.replaceFlower($0)) } ?? false
        let canWin = table.moves.contains(.win)
        let canPass = table.moves.contains(.pass)
        let chows = table.moves.filter { if case .meld(.chow, _) = $0 { true } else { false } }
        let pung = table.moves.first { if case .meld(.pung, _) = $0 { true } else { false } }
        let kongs = table.moves.filter {
            switch $0 {
            case .meld(.openKong, _), .meld(.concealedKong, _), .meld(.addedKong, _): true
            default: false
            }
        }

        return HStack(spacing: 4) {
            if canWin { moveButton(.win, label: title(.win, table: table), table: table) }
            if let pung { moveButton(pung, label: "碰", table: table) }
            meldControl(kongs, label: "杠", table: table)
            meldControl(chows, label: "吃", table: table)
            if canPass {
                moveButton(.pass, label: "过", table: table)
            } else {
                Button {
                    if let selected { send(replacesFlower ? .replaceFlower(selected) : .discard(selected)) }
                } label: {
                    tableControlLabel(replacesFlower ? "补花" : "出牌",
                                      prominent: selected != nil && !canWin && !session.paused, primary: true)
                }
                .buttonStyle(.plain)
                .disabled(selected == nil || session.paused)
                .opacity(selected == nil || session.paused ? 0.5 : 1)
                .accessibilityIdentifier("discard-action")
            }
        }
        .disabled(!active || localDrawInFlight(table))
    }

    private func status(_ table: TableState) -> String {
        if let dealStage { return dealStage.title }
        if let result = table.result {
            return result.winner.map { "\(displayName($0, viewer: table.viewer, names: names)) · \(result.kind?.label ?? "胡")" } ?? "流局"
        }
        if session.paused { return "等待玩家重新连接" }
        if arranging { return arrangementSelection == nil ? "拖动手牌调整顺序" : "轻点目标位置" }
        if table.moves.contains(.win), table.step == .opening { return "可以抢金" }
        if table.step == .opening { return "等待抢金选择" }
        if table.step == .claim { return table.moves.isEmpty ? "等待牌友选择" : "可以响应弃牌" }
        let name = displayName(table.current, viewer: table.viewer, names: names)
        if let drawFlight, drawCue?.seat == table.current {
            return drawFlight.fromReserve ? "\(name)正在补牌" : "\(name)正在摸牌"
        }
        if table.current == table.viewer { return "轮到你出牌" }
        return "\(name)正在选牌"
    }

    @ViewBuilder
    private func meldControl(_ moves: [Move], label: String, table: TableState) -> some View {
        if let first = moves.first {
            if moves.count == 1 {
                moveButton(first, label: label, table: table)
            } else {
                Menu {
                    ForEach(moves, id: \.self) { move in
                        Button(title(move, table: table)) { send(move) }
                    }
                } label: {
                    tableControlLabel(label)
                }
            }
        }
    }

    private func moveButton(_ move: Move, label: String, table: TableState) -> some View {
        Button { send(move) } label: { tableControlLabel(label, prominent: move == .win && !session.paused) }
            .buttonStyle(.plain)
            .accessibilityLabel(title(move, table: table))
            .accessibilityIdentifier(move == .win ? "declare-win" : "table-move-\(label)")
    }

    private func tableControlLabel(_ title: String, prominent: Bool = false, primary: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        return Text(title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(prominent ? TeaTheme.brassInk : TeaTheme.ink)
            .padding(.horizontal, 5)
            .frame(minWidth: primary ? min(112, primaryControlWidth) : TeaTheme.hitTarget, minHeight: TeaTheme.hitTarget)
            .background(prominent ? TeaTheme.brassFinish : TeaTheme.panelFinish, in: shape)
            .overlay { shape.strokeBorder(prominent ? TeaTheme.brass : TeaTheme.line).allowsHitTesting(false) }
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
                "\(kind.label) \(table.hand.first { ids.contains($0.id) }?.kind.spokenName ?? "")"
            }
        default: ""
        }
    }

    private func send(_ move: Move) {
        guard active, !arranging, opening == nil, let table = session.table,
              !localDrawInFlight(table), table.moves.contains(move) else { return }
        if case .discard(let id) = move,
           let tile = table.drawn?.id == id ? table.drawn : table.hand.first(where: { $0.id == id }),
           table.isGold(tile) {
            goldDiscard = GoldDiscard(tile: tile, revision: session.revision, alreadyRestricted: table.viewerMustSelfDraw)
            return
        }
        commit(move)
    }

    private func localDrawInFlight(_ table: TableState) -> Bool {
        !reduceMotion && table.drawn != nil && drawCue?.seat == table.viewer
    }

    private func commit(_ move: Move) {
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
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(table.players) { player in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(table.wind(for: player.seat).wind) · \(displayName(player.seat, viewer: table.viewer, names: names))")
                                .font(.headline)
                                .foregroundStyle(TeaTheme.brass)
                            Text("花牌 \(player.flowerCount) · 积分 \(player.score)")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(TeaTheme.muted)
                            ForEach(player.melds) { meld in
                                MeldTiles(meld: meld, width: 23)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 25), spacing: 4)], spacing: 4) {
                                ForEach(player.discards) { tile in
                                    TileFace(kind: tile.kind, gold: table.isGold(tile)).frame(width: 24, height: 31)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .teaPanel()
                    }
                }
                .padding(TeaTheme.gutter)
                .frame(maxWidth: TeaTheme.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .modifier(HingeSafeContent())
            .teaBackdrop()
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
