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
    @State private var pendingThrow: PendingThrow?
    @State private var discardFlight: DiscardFlight.Motion?
    @State private var arranging = false
    @State private var arrangementSelection: Tile.ID?
    @State private var rackFrame = CGRect.zero
    @State private var goldDiscard: GoldDiscard?
    @State private var previewedMeld: Move?

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
                    .accessibilityHint(arranging ? "结束理牌，回到对局" : "拖动手牌可以调整顺序")
                    Button("出牌记录", systemImage: "square.grid.3x3") { showsHistory = true }
                }
            }
        }
        .fullScreenCover(isPresented: $showsScorecard) { scorecard }
        .sheet(isPresented: $showsHistory) {
            if let table = session.table { TableHistory(table: table, names: names) }
        }
        .sheet(item: $guideLesson) { lesson in
            NavigationStack {
                RuleGuide(startingAt: lesson, showsCloseButton: true,
                          ruleset: session.table?.ruleset ?? .legacy, houseRules: session.table?.houseRules)
            }
        }
        .alert("打出金牌？", isPresented: Binding(get: { goldDiscard != nil }, set: { if !$0 { goldDiscard = nil } }),
               presenting: goldDiscard) { confirmation in
            Button("取消", role: .cancel) { goldDiscard = nil }
            Button("打出金牌", role: .destructive) {
                if session.revision == confirmation.revision {
                    commit(.discard(confirmation.tile.id), throwFrom: confirmation.source)
                }
            }
            .accessibilityIdentifier("confirm-gold-discard")
        } message: { confirmation in
            Text(confirmation.alreadyRestricted
                 ? "你这局已只能自摸。确定要打出\(confirmation.tile.kind.spokenName)金牌吗？"
                 : "\(confirmation.tile.kind.spokenName)是金牌。打出后，这局只能自摸。")
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
        .task(id: pendingThrow) {
            guard let pendingThrow else { return }
            do { try await Task.sleep(for: .seconds(1.5)) }
            catch { return }
            if self.pendingThrow == pendingThrow { self.pendingThrow = nil }
        }
        .task(id: discardFlight) {
            guard let discardFlight else { return }
            do { try await Task.sleep(for: .seconds(0.7)) }
            catch { return }
            if self.discardFlight == discardFlight { self.discardFlight = nil }
        }
        .onChange(of: session.table) { before, after in
            guard let before, let after else { return }
            if let previewedMeld, before.roundNumber != after.roundNumber || before.step != after.step ||
                before.offeredTile != after.offeredTile || !after.moves.contains(previewedMeld) {
                self.previewedMeld = nil
            }
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
                previewedMeld = nil
                resetDiscardMotion()
                if let opening { finishOpening(opening) }
            }
        }
        .onDisappear {
            audio.stop()
            resetDiscardMotion()
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
        if session.players.isEmpty { return access.canBeginSoloHand ? nil : "解锁后继续单机" }
        return access.canHost ? nil : "解锁后继续开桌"
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
        let source: CGRect?
    }

    private struct PendingThrow: Equatable {
        let tileID: Tile.ID
        let source: CGRect
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
        do {
            if reduceMotion {
                play(.shuffle)
                try await Task.sleep(for: .milliseconds(650))
                openingStage = .settled
                play(.deal)
            } else {
                try await performShuffle(round)
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

    private func performShuffle(_ round: Int) async throws {
        let clock = ContinuousClock()
        let began = clock.now
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        if hapticsEnabled {
            heavy.prepare()
            rigid.prepare()
        }
        for (index, sweep) in ShuffleMotion.sweeps.enumerated() {
            try await clock.sleep(until: began.advanced(by: .seconds(sweep.time)))
            guard !Task.isCancelled, active, opening == round else { throw CancellationError() }
            let strongBeat = index.isMultiple(of: 2)
            if hapticsEnabled {
                (strongBeat ? heavy : rigid).impactOccurred()
                (strongBeat ? rigid : heavy).prepare()
            }
            if strongBeat { play(.shuffle) }
        }
        try await clock.sleep(until: began.advanced(by: .seconds(ShuffleMotion.duration)))
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
            resetDiscardMotion()
            return
        }
        let pairs = zip(before.players, after.players)
        let discard = changedDiscard(from: before, to: after)
        if let discard {
            observedDiscard = discard
            if let pendingThrow, pendingThrow.tileID == discard.tile.id, discard.seat == after.viewer,
               after.result == nil, !reduceMotion {
                discardFlight = .init(tile: discard.tile, isGold: after.isGold(discard.tile),
                                      globalSource: pendingThrow.source)
            }
            pendingThrow = nil
        } else if let pendingThrow, !after.moves.contains(.discard(pendingThrow.tileID)) {
            self.pendingThrow = nil
        }
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
                            tableSurface(table, drawsOnBoard: false)
                        }
                        .padding(TeaTheme.tableGutter)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("table-region")
                    } secondary: {
                        GeometryReader { panel in
                            let singleRow = panel.size.width >= 600
                            VStack(alignment: .leading, spacing: 6) {
                                if !singleRow { drawSlot(table.drawn, table: table) }
                                rack(table, availableWidth: panel.size.width, landscape: singleRow)
                            }
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
                if !reduceMotion, dealStage != nil || drawFlight != nil || discardFlight != nil {
                    GeometryReader { overlay in
                        tableMotion(table, anchors: anchors.mapValues { overlay[$0] }, geometry: overlay)
                            .mask { motionArea(overlay.size, excluding: divisions) }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlayPreferenceValue(DiscardDragPreview.Key.self) { preview in
                if !reduceMotion, active, let preview {
                    GeometryReader { overlay in
                        let origin = overlay[preview.source]
                        let frame = DiscardFlight.inside(origin.offsetBy(dx: preview.translation.width,
                                                                       dy: preview.translation.height),
                                                        size: overlay.size)
                        TileFace(kind: preview.tile.kind, gold: preview.isGold, selected: true)
                            .frame(width: frame.width, height: frame.height)
                            .shadow(color: .black.opacity(0.46), radius: 6, y: 4)
                            .position(x: frame.midX, y: frame.midY)
                            .mask { motionArea(overlay.size, excluding: divisions) }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: geometry.size) { _, _ in
                resetDiscardMotion()
                if let goldDiscard {
                    self.goldDiscard = GoldDiscard(tile: goldDiscard.tile, revision: goldDiscard.revision,
                                                   alreadyRestricted: goldDiscard.alreadyRestricted, source: nil)
                }
            }
        }
    }

    private func motionArea(_ size: CGSize, excluding divisions: [CGRect]) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRects(divisions)
        }
        .fill(style: FillStyle(eoFill: true))
    }

    private func tableMotion(_ table: TableState, anchors: [TableAnchors.Marker: CGRect],
                             geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            if let dealStage {
                OpeningDeal(viewer: table.viewer, dealer: table.dealer, stage: dealStage, anchors: anchors)
            } else if let drawFlight, let seat = drawCue?.seat,
                      let source = anchors[drawFlight.fromReserve ? .reserve : .wall],
                      let destination = anchors[seat == table.viewer ? .drawn : .player(seat)] {
                DrawPickup(flight: drawFlight, source: source, destination: destination, isLocal: seat == table.viewer)
            }
            if let discardFlight, let destination = anchors[.latestDiscard],
               (table.latestDiscard ?? observedDiscard)?.tile.id == discardFlight.tile.id {
                let origin = geometry.frame(in: .global).origin
                let source = discardFlight.globalSource.offsetBy(dx: -origin.x, dy: -origin.y)
                DiscardFlight(motion: discardFlight, source: DiscardFlight.inside(source, size: geometry.size),
                              destination: destination) {
                    if self.discardFlight == discardFlight { self.discardFlight = nil }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func flatBoard(_ table: TableState, size: CGSize) -> some View {
        let landscape = size.width > size.height
        let singleRow = landscape || size.width >= 600
        return VStack(spacing: 6) {
            header(table)
            tableSurface(table, drawsOnBoard: !singleRow)
            rack(table, availableWidth: max(0, size.width - TeaTheme.tableGutter * 2),
                 landscape: singleRow)
        }
        .padding(.horizontal, TeaTheme.tableGutter)
        .padding(.vertical, 4)
    }

    private func tableSurface(_ table: TableState, drawsOnBoard: Bool) -> some View {
        GeometryReader { surface in
            LiveTable(table: table, names: names, latest: table.latestDiscard ?? observedDiscard,
                      opening: dealStage, drawingFromReserve: drawFlight?.fromReserve,
                      paused: session.paused, size: surface.size, showsDrawDock: drawsOnBoard,
                      flyingDiscard: reduceMotion ? nil : discardFlight?.tile.id) {
                tableActions(table)
            } drawDock: {
                drawSlot(table.drawn, table: table)
            }
        }
    }

    @ViewBuilder
    private func tableActions(_ table: TableState) -> some View {
        if opening == nil, table.result == nil, active, arranging || !table.moves.isEmpty {
            let responding = !arranging && (table.step == .claim || table.step == .opening)
            Group {
                if arranging { arrangementControls }
                else { actions(table) }
            }
            .padding(4)
            .teaPanel(corner: 14, emphasized: responding)
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("table-actions")
            .frame(maxWidth: .infinity, alignment: responding ? .center : .trailing)
            .padding(.top, 4)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
            if let opening {
                Button { finishOpening(opening) } label: { tableControlLabel("跳过动画", primary: true) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("skip-opening")
            } else if let gold = table.gold {
                Button { guideLesson = .gold } label: { goldIndicator(gold.kind) }
                    .buttonStyle(.plain)
                    .opacity(gold.id == table.result?.winningTile?.id ? 0 : 1)
                    .allowsHitTesting(gold.id != table.result?.winningTile?.id)
                    .accessibilityHidden(gold.id == table.result?.winningTile?.id)
                    .accessibilityHint("查看金牌玩法")
                    .accessibilityIdentifier("gold-rules")
            }
            if table.result != nil {
                Button { showsScorecard = true } label: {
                    tableControlLabel("查看结算", prominent: true, primary: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("view-scorecard")
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
            Text(kind.suit == .dragon && kind.rank == 3 ? "白板 · 金牌" : "金牌")
                .font(.caption.weight(.semibold)).foregroundStyle(TeaTheme.brass)
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
        let highlighted = highlightedMeldTiles(table)
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
                                tileButton(tile, table: table, rackCellWidth: cellWidth,
                                           isMeldCandidate: highlighted.contains(tile.id))
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
            Text("刚摸到")
                .font(.caption2.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(TeaTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .opacity(visible ? 1 : 0)
                .accessibilityHidden(true)
            Group {
                if let tile {
                    tileButton(tile, table: table, rackCellWidth: rackCellWidth, isDrawn: true,
                               isMeldCandidate: highlightedMeldTiles(table).contains(tile.id))
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawn-tile-dock")
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

    private func highlightedMeldTiles(_ table: TableState) -> Set<Tile.ID> {
        guard active, !arranging, opening == nil, !localDrawInFlight(table) else { return [] }
        if let previewedMeld, table.moves.contains(previewedMeld), let meld = previewedMeld.meld {
            return Set(meld.ids)
        }
        return Set(table.moves.compactMap(\.meld).flatMap(\.ids))
    }

    private func tileButton(_ tile: Tile, table: TableState, rackCellWidth: CGFloat? = nil,
                            isDrawn: Bool = false, isMeldCandidate: Bool) -> some View {
        let playable = active && !arranging && opening == nil && !localDrawInFlight(table)
        let canDiscard = playable && table.moves.contains(.discard(tile.id))
        let canSelect = canDiscard || (playable && table.moves.contains(.replaceFlower(tile.id)))
        return RackTile(tile: tile, isGold: table.isGold(tile), isSelected: playable && tile.id == activeTile(table),
                        isDrawn: isDrawn, isMeldCandidate: isMeldCandidate,
                        canSelect: canSelect, canDiscard: canDiscard, rackCellWidth: rackCellWidth, select: {
            guard selectedID != tile.id else { return }
            if reduceMotion { selectedID = tile.id }
            else { withAnimation(.easeOut(duration: 0.15)) { selectedID = tile.id } }
            if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        }, discard: {
            send(.discard(tile.id))
        }, throwDiscard: { origin, released in
            send(.discard(tile.id), throwFrom: table.isGold(tile) ? origin : released)
        })
    }

    private func actions(_ table: TableState) -> some View {
        Group {
            if let previewedMeld, table.moves.contains(previewedMeld), let meld = previewedMeld.meld {
                meldConfirmation(previewedMeld, kind: meld.kind, table: table)
            } else {
                availableActions(table)
            }
        }
        .disabled(!active || pendingThrow != nil || localDrawInFlight(table))
    }

    private func availableActions(_ table: TableState) -> some View {
        let selected = activeTile(table)
        let replacesFlower = selected.map { table.moves.contains(.replaceFlower($0)) } ?? false
        let canWin = table.moves.contains(.win)
        let canPass = table.moves.contains(.pass)
        let melds = table.moves.filter { $0.meld != nil }

        return HStack(spacing: 4) {
            if canWin { moveButton(.win, label: title(.win, table: table), table: table) }
            meldControl(melds, label: "碰", table: table)
            meldControl(melds, label: "杠", table: table)
            meldControl(melds, label: "吃", table: table)
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
    }

    private func status(_ table: TableState) -> String {
        if let dealStage { return dealStage.title }
        if let result = table.result {
            return result.winner.map { "\(displayName($0, viewer: table.viewer, names: names)) · \(result.winTitle)" } ?? "流局"
        }
        if session.paused { return "等待牌友重新连接" }
        if arranging { return arrangementSelection == nil ? "拖动手牌调整顺序" : "点一下要移到的位置" }
        if table.moves.contains(.win), table.step == .opening { return "可以抢金，也可以过" }
        if table.step == .opening { return "等待牌友决定是否抢金" }
        if table.step == .claim { return table.moves.isEmpty ? "等待牌友要牌或过牌" : "可以要这张牌，也可以过" }
        let name = displayName(table.current, viewer: table.viewer, names: names)
        if let drawFlight, drawCue?.seat == table.current {
            return drawFlight.fromReserve ? "\(name)正在补牌" : "\(name)正在摸牌"
        }
        if table.current == table.viewer { return "轮到你了" }
        return "轮到\(name)了"
    }

    @ViewBuilder
    private func meldControl(_ moves: [Move], label: String, table: TableState) -> some View {
        if let first = moves.first(where: { $0.meld?.kind.actionLabel == label }) {
            Button {
                if moves.count == 1 { send(first) }
                else { previewedMeld = first }
            } label: {
                tableControlLabel(label)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(moves.count == 1 ? title(first, table: table) : label)
            .accessibilityIdentifier("table-move-\(label)")
        }
    }

    private func meldConfirmation(_ move: Move, kind: MeldKind, table: TableState) -> some View {
        let alternatives = table.moves.filter { $0.meld?.kind.actionLabel == kind.actionLabel }
        return HStack(spacing: 4) {
            Button { previewedMeld = nil } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: TeaTheme.hitTarget, minHeight: TeaTheme.hitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回牌桌选项")
            .accessibilityIdentifier("cancel-meld-preview")

            if alternatives.count > 1 {
                Menu {
                    ForEach(Array(alternatives.enumerated()), id: \.element) { index, option in
                        Button {
                            previewedMeld = option
                            if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
                        } label: {
                            if option == move { Label(title(option, table: table), systemImage: "checkmark") }
                            else { Text(title(option, table: table)) }
                        }
                        .accessibilityIdentifier("meld-option-\(index)")
                    }
                } label: {
                    HStack(spacing: 3) {
                        meldTilesPreview(move, table: table)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .frame(minHeight: TeaTheme.hitTarget)
                }
                .accessibilityLabel("选择\(kind.actionLabel)牌组")
                .accessibilityValue(title(move, table: table))
                .accessibilityIdentifier("meld-options")
            } else {
                meldTilesPreview(move, table: table)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title(move, table: table))
            }
            Button { send(move) } label: {
                tableControlLabel("确认\(kind.label)", prominent: !table.moves.contains(.win))
            }
                .buttonStyle(.plain)
                .accessibilityIdentifier("confirm-meld")
            if table.moves.contains(.win) { moveButton(.win, label: title(.win, table: table), table: table) }
        }
    }

    private func meldTilesPreview(_ move: Move, table: TableState) -> some View {
        HStack(spacing: 1) {
            ForEach(meldTiles(for: move, table: table)) { tile in
                TileFace(kind: tile.kind)
                    .frame(width: 13, height: 13 / TileFace.artworkAspectRatio)
                    .accessibilityHidden(true)
            }
        }
    }

    private func meldTiles(for move: Move, table: TableState) -> [Tile] {
        guard let meld = move.meld else { return [] }
        let rack = table.hand + [table.drawn].compactMap { $0 }
        let offered = table.step == .claim ? [table.offeredTile].compactMap { $0 } : []
        return (rack.filter { meld.ids.contains($0.id) } + offered).sorted { $0.kind < $1.kind }
    }

    private func moveButton(_ move: Move, label: String, table: TableState) -> some View {
        Button { send(move) } label: {
            tableControlLabel(label, prominent: move == .win && !session.paused, winning: move == .win)
        }
            .buttonStyle(.plain)
            .accessibilityLabel(title(move, table: table))
            .accessibilityIdentifier(move == .win ? "declare-win" : "table-move-\(label)")
    }

    private func tableControlLabel(_ title: String, prominent: Bool = false, primary: Bool = false,
                                   winning: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        return Text(title)
            .font(winning ? .title3.weight(.bold) : .subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(prominent ? TeaTheme.brassInk : TeaTheme.ink)
            .padding(.horizontal, 5)
            .frame(minWidth: winning ? 64 : primary ? min(112, primaryControlWidth) : TeaTheme.hitTarget,
                   minHeight: winning ? 48 : TeaTheme.hitTarget)
            .background(prominent ? TeaTheme.brassFinish : TeaTheme.panelFinish, in: shape)
            .overlay { shape.strokeBorder(prominent ? TeaTheme.brass : TeaTheme.line).allowsHitTesting(false) }
    }

    private func title(_ move: Move, table: TableState) -> String {
        switch move {
        case .win:
            return switch table.step {
            case .opening: "抢金"
            case .claim: "胡"
            default: table.canDeclareThreeGold ? "三金倒" : "自摸"
            }
        case .pass: return "过"
        case .meld(let kind, _):
            let tiles = meldTiles(for: move, table: table)
            if kind == .chow {
                return "吃 \(tiles.map(\.kind.spokenName).joined(separator: "、"))"
            } else {
                return "\(kind.label) \(tiles.first?.kind.spokenName ?? "")"
            }
        default: return ""
        }
    }

    private func send(_ move: Move, throwFrom source: CGRect? = nil) {
        guard active, !arranging, opening == nil, let table = session.table,
              pendingThrow == nil, !localDrawInFlight(table), table.moves.contains(move) else { return }
        if case .discard(let id) = move,
           let tile = table.drawn?.id == id ? table.drawn : table.hand.first(where: { $0.id == id }),
           table.isGold(tile) {
            goldDiscard = GoldDiscard(tile: tile, revision: session.revision, alreadyRestricted: table.viewerMustSelfDraw,
                                      source: source)
            return
        }
        commit(move, throwFrom: source)
    }

    private func localDrawInFlight(_ table: TableState) -> Bool {
        !reduceMotion && table.drawn != nil && drawCue?.seat == table.viewer
    }

    private func commit(_ move: Move, throwFrom source: CGRect? = nil) {
        guard active, !arranging, opening == nil, session.table?.moves.contains(move) == true else { return }
        if let source, !reduceMotion, case .discard(let id) = move {
            pendingThrow = PendingThrow(tileID: id, source: source)
        }
        guard session.submit(move) else {
            pendingThrow = nil
            return
        }
        previewedMeld = nil
        selectedID = nil
        guard hapticsEnabled else { return }
        if move == .win { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else if case .discard = move { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    private func resetDiscardMotion() {
        pendingThrow = nil
        discardFlight = nil
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
            .navigationTitle("出牌与亮牌记录")
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
    fileprivate var actionLabel: String {
        switch self { case .chow, .pung: label; case .openKong, .concealedKong, .addedKong: "杠" }
    }

    var label: String {
        switch self { case .chow: "吃"; case .pung: "碰"; case .openKong: "明杠"; case .concealedKong: "暗杠"; case .addedKong: "加杠" }
    }
}

private extension Move {
    var meld: (kind: MeldKind, ids: [Tile.ID])? {
        if case .meld(let kind, let ids) = self { return (kind, ids) }
        return nil
    }
}
