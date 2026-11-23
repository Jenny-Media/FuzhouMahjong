import FuzhouAccess
import FuzhouCore
import SwiftUI
import UIKit

struct FlowerHighlights {
    private var deadlines: [Tile.ID: ContinuousClock.Instant] = [:]

    var tiles: Set<Tile.ID> { Set(deadlines.keys) }
    var nextExpiry: ContinuousClock.Instant? { deadlines.values.min() }

    mutating func reveal(_ tiles: Set<Tile.ID>, at time: ContinuousClock.Instant) {
        expire(at: time)
        let expiry = time.advanced(by: .milliseconds(900))
        for tile in tiles { deadlines[tile] = expiry }
    }

    mutating func expire(at time: ContinuousClock.Instant) {
        deadlines = deadlines.filter { $0.value > time }
    }
}

struct MatchView<Session: MatchSession>: View {
    let session: Session
    @Environment(GameAccess.self) private var access
    @State private var purchaseReason: AccessReason?
    @State private var tablePurchaseReason: AccessReason?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardStyle) private var boardStyle
    @Environment(\.tileStyle) private var tileStyle
    @ScaledMetric(relativeTo: .subheadline) private var primaryControlWidth = 80.0
    @AppStorage("practice.haptics.enabled") private var hapticsEnabled = true
    @AppStorage("table.sound.enabled") private var soundEnabled = true
    @AppStorage("table.sound.nearbyOwnMovesOnly") private var nearbyOwnMovesOnly = true
    @State private var selectedID: Tile.ID?
    @State private var inspectedSeat: Seat?
    @State private var showsHistory = false
    @State private var guideLesson: RuleLesson?
    @State private var showsScorecard = false
    @State private var openingStage = OpeningDeal.Stage.shuffle(nil)
    @State private var openingAnimationRound: Int?
    @State private var openingSkipHeld = false
    @State private var audio = TableAudio()
    @State private var touch = TableTouch()
    @State private var observedDiscard: TableDiscard?
    @State private var drawCue: DrawCue?
    @State private var drawFlight: DrawPickup.Flight?
    @State private var flowerHighlights = FlowerHighlights()
    @State private var pendingThrow: PendingThrow?
    @State private var discardFlight: DiscardFlight.Motion?
    @State private var offeredTileFrame: OfferedTileFrame?
    @State private var claimFlight: DiscardFlight.Motion?
    @State private var presentedClaimFlightID: UUID?
    @State private var arranging = false
    @State private var arrangementSelection: Tile.ID?
    @State private var rackFrame = CGRect.zero
    @State private var goldDiscard: GoldDiscard?
    @State private var meldPreview: MeldPreview?
    @State private var robGoldChoice: RobGoldChoice?

    private var opening: Int? { session.openingRound }
    private var active: Bool { scenePhase == .active && !session.paused }
    private var playsHaptics: Bool { hapticsEnabled && active && !showsScorecard && !showsHistory && guideLesson == nil }
    private var feedbackProfile: TableFeedbackProfile {
        TableFeedbackProfile(tile: tileStyle.material, surface: boardStyle.surface)
    }
    private var dealStage: OpeningDeal.Stage? {
        guard let opening else { return nil }
        return openingAnimationRound == opening ? openingStage : .shuffle(nil)
    }
    private var showsGoldIndicator: Bool { opening == nil || dealStage == .revealGold }

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
                        meldPreview = nil
                        robGoldChoice = nil
                    }
                    .disabled(session.table?.hand.isEmpty != false)
                    .accessibilityIdentifier("rack-arrange")
                    .accessibilityHint(arranging ? "结束理牌，回到对局" : "拖动手牌可以调整顺序")
                    Button("出牌记录", systemImage: "square.grid.3x3") { showsHistory = true }
                }
            }
        }
        .fullScreenCover(isPresented: $showsScorecard) { scorecard }
        .sheet(item: $tablePurchaseReason) { PurchaseSheet(reason: $0) }
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
        .task(id: feedbackProfile) {
            if soundEnabled { audio.prepare(for: feedbackProfile) }
            if playsHaptics { touch.prepare(for: feedbackProfile) }
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
        .task(id: flowerHighlights.nextExpiry) { [expiry = flowerHighlights.nextExpiry] in
            guard let expiry else { return }
            let clock = ContinuousClock()
            do { try await clock.sleep(until: expiry) }
            catch { return }
            guard !Task.isCancelled else { return }
            flowerHighlights.expire(at: clock.now)
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
            finishDiscardLanding(discardFlight)
        }
        .task(id: claimFlight) {
            guard let claimFlight else { return }
            do { try await Task.sleep(for: .seconds(0.7)) }
            catch { return }
            finishClaimLanding(claimFlight)
        }
        .onChange(of: session.table) { before, after in
            guard let before, let after else { return }
            if let meldPreview, before.roundNumber != after.roundNumber || before.step != after.step ||
                before.current != after.current || before.offeredTile != after.offeredTile ||
                !meldPreview.options.allSatisfy(after.moves.contains) {
                self.meldPreview = nil
            }
            if before.roundNumber != after.roundNumber || before.gold != after.gold || after.step != .opening ||
                before.robGoldDiscardIDs != after.robGoldDiscardIDs || !after.moves.contains(.win) {
                robGoldChoice = nil
            }
            readTableChange(from: before, to: after)
        }
        .onChange(of: soundEnabled) { _, enabled in
            if !enabled { audio.stop() }
        }
        .onChange(of: playsHaptics) { _, enabled in
            if enabled { touch.prepare(for: feedbackProfile) }
            else { touch.stop() }
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
                flowerHighlights = FlowerHighlights()
                goldDiscard = nil
                meldPreview = nil
                robGoldChoice = nil
                resetDiscardMotion()
                if let opening { finishOpening(opening) }
            }
        }
        .onDisappear {
            audio.stop()
            touch.stop()
            flowerHighlights = FlowerHighlights()
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
                    let message = [status(table), table.discardClaimFeedback?.message].compactMap { $0 }.joined(separator: "。")
                    AccessibilityNotification.Announcement(message).post()
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
        guard session.canAdvance, !session.paused, session.table?.result != nil else { return }
        access.refreshClock()
        let reason: AccessReason? = if session.players.isEmpty {
            access.canBeginSoloHand ? nil : .solo
        } else {
            access.authorizeHosting() ? nil : .hosting
        }
        if let reason {
            if showsScorecard { purchaseReason = reason }
            else { tablePurchaseReason = reason }
            return
        }
        selectedID = nil
        openingAnimationRound = nil
        session.nextHand()
    }

    private struct TurnState: Equatable { var revision: Int; var ready: Bool }
    private struct MeldPreview: Equatable {
        let options: [Move]
        var selected: Move?

        var highlightedMoves: [Move] { selected.map { [$0] } ?? options }
    }
    private enum RobGoldChoice: Equatable {
        case choosing, selected(Tile.ID)

        var tileID: Tile.ID? {
            if case .selected(let id) = self { id } else { nil }
        }
    }
    private struct OfferedTileFrame {
        let round: Int
        let tileID: Tile.ID
        let bounds: CGRect
    }
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
    private enum TableHaptic {
        case selection, contact(TableImpact), gold, win
    }
    private struct DrawCue {
        let id = UUID()
        let seat: Seat
        let contactDelay: Duration
        let fromReserve: Bool
        let replacesFlowers: Bool
    }

    private func performOpening(_ round: Int) async {
        let dealsDealerTile = session.table?.lastDraw?.isOpeningDeal == true
        openingAnimationRound = round
        openingStage = .shuffle(reduceMotion ? nil : .now)
        do {
            if reduceMotion {
                playHaptic(.contact(.shuffle))
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
                if dealsDealerTile {
                    try await clock.sleep(until: dealStart.advanced(by: .seconds(OpeningDeal.dealerArrival)))
                    play(.deal)
                } else {
                    try await Task.sleep(for: .milliseconds(280))
                }
            }
            if session.table?.players.contains(where: { $0.flowerCount > 0 }) == true {
                openingStage = .flowers
                try await Task.sleep(for: .milliseconds(350))
            }
            if session.table?.gold != nil {
                guard !Task.isCancelled, active, opening == round else { return }
                openingStage = .revealGold
                playHaptic(.gold)
                try await Task.sleep(for: .milliseconds(500))
            }
        } catch { return }
        guard !Task.isCancelled else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-manual-opening") { return }
        #endif
        finishOpening(round, animateDraw: !dealsDealerTile)
    }

    private func performShuffle(_ round: Int) async throws {
        let clock = ContinuousClock()
        let began = clock.now
        if playsHaptics { touch.prepare(for: feedbackProfile) }
        for (index, sweep) in ShuffleMotion.sweeps.enumerated() {
            try await clock.sleep(until: began.advanced(by: .seconds(sweep.time)))
            guard !Task.isCancelled, active, opening == round else { throw CancellationError() }
            let strongBeat = index.isMultiple(of: 2)
            playHaptic(.contact(strongBeat ? .shuffle : .sweep))
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
            drawCue = DrawCue(seat: table.current, contactDelay: .zero,
                              fromReserve: table.lastDraw?.fromReserve == true,
                              replacesFlowers: (table.lastDraw?.flowersReplaced ?? 0) > 0)
        }
    }

    private func performDraw(_ cue: DrawCue) async {
        var landed = false
        defer {
            if drawCue?.id == cue.id {
                drawFlight = nil
                drawCue = nil
                if landed, !Task.isCancelled { playDrawHaptic(for: cue) }
            }
        }
        do {
            if cue.contactDelay > .zero { try await Task.sleep(for: cue.contactDelay) }
            guard !Task.isCancelled, active, session.table?.current == cue.seat else { return }
            if reduceMotion {
                landed = true
                return
            }
            drawFlight = .init(fromReserve: cue.fromReserve || cue.replacesFlowers)
            try await Task.sleep(for: .seconds(DrawPickup.duration))
            landed = true
        } catch { return }
    }

    private func playDrawHaptic(for cue: DrawCue) {
        guard opening == nil, !arranging, let table = session.table, table.step == .turn,
              cue.seat == table.viewer, table.current == cue.seat, table.drawn != nil else { return }
        playHaptic(.contact(.draw))
    }

    private func readTableChange(from before: TableState, to after: TableState) {
        guard active, opening == nil, before.roundNumber == after.roundNumber else {
            observedDiscard = nil
            drawCue = nil
            flowerHighlights = FlowerHighlights()
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
                                      globalSource: pendingThrow.source, seat: discard.seat, impact: .discard)
            }
            pendingThrow = nil
        } else if let pendingThrow, !after.moves.contains(.discard(pendingThrow.tileID)) {
            self.pendingThrow = nil
        }
        let meldingPlayer = pairs.first { $1.melds != $0.melds }
        let meld = meldingPlayer.flatMap { old, new in new.melds.first { !old.melds.contains($0) } }
        let contact = discard != nil || meld != nil
        var contactDelay: Duration = contact ? .milliseconds(168) : .zero
        var animatesMeld = false
        if before.step == .claim, let (_, player) = meldingPlayer, let meld, let claimed = before.latestDiscard,
           meld.from == claimed.seat, meld.tiles.contains(claimed.tile),
           meld.kind == .chow || meld.kind == .pung || meld.kind == .openKong {
            if after.latestDiscard == nil, discard == nil { observedDiscard = claimed }
            if !reduceMotion, let frame = offeredTileFrame,
               frame.round == before.roundNumber, frame.tileID == claimed.id {
                if discardFlight?.tile.id == claimed.id { discardFlight = nil }
                claimFlight = .init(tile: claimed.tile, isGold: before.isGold(claimed.tile), globalSource: frame.bounds,
                                    seat: player.seat, impact: TableImpact(meld: meld.kind))
                animatesMeld = true
                contactDelay = .seconds(DiscardFlight.duration)
            }
        }
        let replacedFlower = pairs.contains { $1.flowerCount > $0.flowerCount }
        if replacedFlower {
            let flowers = Set(pairs.flatMap { before, after in
                let added = max(0, after.flowerCount - before.flowerCount)
                return (after.exposedFlowers ?? []).suffix(added).map(\.id)
            })
            if !flowers.isEmpty { flowerHighlights.reveal(flowers, at: .now) }
        }
        if before.result == nil, let winner = after.result?.winner {
            play(.win, by: winner)
            if winner == after.viewer { playHaptic(.win) }
        } else if let (_, player) = meldingPlayer, let meld {
            if !animatesMeld {
                playContact(TableImpact(meld: meld.kind), seat: player.seat)
            }
        } else if let discard, discardFlight?.tile.id != discard.tile.id {
            playContact(.discard, seat: discard.seat)
        }

        let legacyDraw = after.remaining < before.remaining || (after.drawn != nil && after.drawn != before.drawn) ||
            replacedFlower || meld.map { $0.kind != .chow && $0.kind != .pung } == true
        if after.step == .turn, let draw = after.lastDraw, draw != before.lastDraw {
            drawCue = DrawCue(seat: draw.seat, contactDelay: contactDelay, fromReserve: draw.fromReserve,
                              replacesFlowers: draw.flowersReplaced > 0)
        } else if after.step == .turn, after.lastDraw == nil, legacyDraw {
            drawCue = DrawCue(seat: after.current, contactDelay: contactDelay, fromReserve: meld != nil,
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
        audio.play(cue, profile: feedbackProfile, volume: isNearby ? 0.64 : 0.85)
    }

    private func playContact(_ impact: TableImpact, seat: Seat) {
        if let sound = impact.sound { play(sound, by: seat) }
        if seat == session.table?.viewer { playHaptic(.contact(impact)) }
    }

    private func finishDiscardLanding(_ flight: DiscardFlight.Motion) {
        guard discardFlight == flight else { return }
        discardFlight = nil
        playContact(flight.impact, seat: flight.seat)
    }

    private func finishClaimLanding(_ flight: DiscardFlight.Motion) {
        guard claimFlight == flight else { return }
        claimFlight = nil
        playContact(flight.impact, seat: flight.seat)
    }

    private func playHaptic(_ cue: TableHaptic) {
        guard playsHaptics else { return }
        switch cue {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .contact(let impact): touch.play(impact, profile: feedbackProfile)
        case .gold: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .win: UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
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
                                if !singleRow {
                                    drawSlot(table.drawn, table: table)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
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
                if !reduceMotion, dealStage != nil || drawFlight != nil || discardFlight != nil || claimFlight != nil {
                    GeometryReader { overlay in
                        tableMotion(table, anchors: anchors.mapValues { overlay[$0] }, geometry: overlay)
                            .mask { motionArea(overlay.size, excluding: divisions) }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlayPreferenceValue(TableAnchors.self) { anchors in
                if let opening, active, !showsScorecard, let center = anchors[.center] {
                    GeometryReader { overlay in
                        let target = overlay[center]
                        OpeningSkipTarget(size: target.size, isHolding: $openingSkipHeld) {
                            guard active, self.opening == opening else { return }
                            playHaptic(.selection)
                            finishOpening(opening)
                        }
                        .id(opening)
                        .position(x: target.midX, y: target.midY)
                    }
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
                OpeningDeal(viewer: table.viewer, dealer: table.dealer, dealsDealerTile: table.lastDraw?.isOpeningDeal == true,
                            stage: dealStage, anchors: anchors)
            } else if let drawFlight, let seat = drawCue?.seat,
                      let source = anchors[drawFlight.fromReserve ? .reserve : .wall],
                      let destination = anchors[seat == table.viewer ? .drawn : .player(seat)] {
                DrawPickup(flight: drawFlight, source: source, destination: destination, isLocal: seat == table.viewer)
            }
            if let discardFlight, let destination = anchors[.latestDiscard],
               (table.latestDiscard ?? observedDiscard)?.tile.id == discardFlight.tile.id {
                let origin = geometry.frame(in: .global).origin
                let source = discardFlight.globalSource.offsetBy(dx: -origin.x, dy: -origin.y)
                DiscardFlight(tile: discardFlight.tile, isGold: discardFlight.isGold, id: discardFlight.id,
                              source: DiscardFlight.inside(source, size: geometry.size),
                              destination: destination) {
                    finishDiscardLanding(discardFlight)
                }
            }
            if let claimFlight, let destination = anchors[.meldTile(claimFlight.tile.id)], !destination.isEmpty {
                let origin = geometry.frame(in: .global).origin
                let source = claimFlight.globalSource.offsetBy(dx: -origin.x, dy: -origin.y)
                DiscardFlight(tile: claimFlight.tile, isGold: claimFlight.isGold, id: claimFlight.id,
                              source: source, destination: destination) {
                    finishClaimLanding(claimFlight)
                }
                .onAppear { presentedClaimFlightID = claimFlight.id }
                .onDisappear {
                    if presentedClaimFlightID == claimFlight.id { presentedClaimFlightID = nil }
                }
                .id(claimFlight.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func flatBoard(_ table: TableState, size: CGSize) -> some View {
        let landscape = size.width > size.height
        let singleRow = landscape || size.width >= 600
        return VStack(spacing: 6) {
            header(table, showsResultActions: landscape)
            tableSurface(table, drawsOnBoard: !singleRow, showsResultActions: !landscape)
            rack(table, availableWidth: max(0, size.width - TeaTheme.tableGutter * 2),
                 landscape: singleRow)
        }
        .padding(.horizontal, TeaTheme.tableGutter)
        .padding(.vertical, 4)
    }

    private func tableSurface(_ table: TableState, drawsOnBoard: Bool, showsResultActions: Bool = true) -> some View {
        GeometryReader { surface in
            LiveTable(table: table, names: names, latest: table.latestDiscard ?? observedDiscard,
                      opening: dealStage, drawingFromReserve: drawFlight?.fromReserve, pendingDraw: drawCue?.seat,
                      highlightedFlowers: flowerHighlights.tiles,
                      paused: session.paused, size: surface.size, showsDrawDock: drawsOnBoard,
                      flyingDiscard: reduceMotion ? nil : discardFlight?.tile.id,
                      flyingClaim: !reduceMotion && presentedClaimFlightID == claimFlight?.id ? claimFlight?.tile.id : nil,
                      inspectedSeat: $inspectedSeat, onOfferedTileFrame: rememberOfferedTileFrame) {
                tableActions(table, showsResultActions: showsResultActions)
            } drawDock: {
                drawSlot(table.drawn, table: table)
            }
        }
    }

    private func rememberOfferedTileFrame(_ id: Tile.ID, bounds: CGRect) {
        guard !reduceMotion, !bounds.isEmpty, let table = session.table,
              table.step == .claim, table.offeredTile?.id == id else { return }
        offeredTileFrame = OfferedTileFrame(round: table.roundNumber, tileID: id, bounds: bounds)
    }

    @ViewBuilder
    private func tableActions(_ table: TableState, showsResultActions: Bool) -> some View {
        if let result = table.result {
            if showsResultActions { resultActions(table, result: result, fillsWidth: true) }
        } else if opening == nil, scenePhase == .active,
                  arranging || (!session.paused && session.moveStatus == nil && !table.moves.isEmpty) {
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

    private func resultActions(_ table: TableState, result: RoundResult, fillsWidth: Bool) -> some View {
        let delta = result.delta(for: table.viewer)
        let score = delta > 0 ? "+\(delta)" : "\(delta)"
        return HStack(spacing: 6) {
            Text("本局 \(score)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(delta > 0 ? TeaTheme.gain : delta < 0 ? TeaTheme.loss : TeaTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel("本局积分变化 \(score)")
                .accessibilityIdentifier("table-score-delta")
            if fillsWidth { Spacer(minLength: 0) }
            Button { showsScorecard = true } label: { tableControlLabel("查看结算", primary: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("view-scorecard")
            if session.canAdvance {
                Button(action: nextHand) {
                    tableControlLabel(advanceTitle ?? (table.matchFinished ? "新开一场" : "下一局"),
                                      prominent: active, primary: true)
                }
                .buttonStyle(.plain)
                .disabled(!active)
                .accessibilityIdentifier("table-next-hand")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, fillsWidth ? 4 : 0)
        .teaPanel(corner: 14)
        .padding(.top, fillsWidth ? 4 : 0)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func header(_ table: TableState, showsResultActions: Bool = false) -> some View {
        let resultFeedback = table.result == nil ? nil : table.discardClaimFeedback?.message
        let showsStatus = table.result == nil || resultFeedback != nil
        return HStack(spacing: 6) {
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
                    Text(resultFeedback ?? status(table))
                        .foregroundStyle(!session.paused && (!table.moves.isEmpty || session.moveStatus != nil || table.discardClaimFeedback != nil) ? TeaTheme.brass : TeaTheme.ink)
                        .layoutPriority(table.result == nil && table.viewerMustSelfDraw ? 0 : 1)
                        .accessibilityIdentifier("table-status")
                        .opacity(showsStatus ? 1 : 0)
                        .accessibilityHidden(!showsStatus)
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
                Button { finishOpening(opening) } label: {
                    tableControlLabel("跳过动画", primary: true, holdProgress: openingSkipHeld)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("skip-opening")
            }
            if showsGoldIndicator, let gold = table.gold {
                Button { guideLesson = .gold } label: { goldIndicator(gold.kind) }
                    .buttonStyle(.plain)
                    .opacity(gold.id == table.result?.winningTile?.id ? 0 : 1)
                    .allowsHitTesting(gold.id != table.result?.winningTile?.id)
                    .accessibilityHidden(gold.id == table.result?.winningTile?.id)
                    .accessibilityHint("查看金牌玩法")
                    .accessibilityIdentifier("gold-rules")
            }
            if showsResultActions, let result = table.result {
                resultActions(table, result: result, fillsWidth: false)
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
        let rackMelds = availableRackMelds(table)
        let rackHeight = landscape ? cellHeight : cellHeight * 2 + 4
        let columns = Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: count)
        return HStack(alignment: .bottom, spacing: 0) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: dealStage?.isDealing != true)) { time in
                let landed = dealStage?.landed(for: table.viewer, dealer: table.dealer, at: time.date) ?? tiles.count
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                        Group {
                            if arranging {
                                RackTile(tile: tile, isGold: showsGoldIndicator && table.isGold(tile),
                                         isSelected: tile.id == arrangementSelection,
                                         canSelect: true, canDiscard: false, rackCellWidth: cellWidth, select: {
                                    selectForArrangement(tile.id, at: index)
                                }, discard: {}, reposition: { point in
                                    finishReorder(tile.id, at: point, columns: count, tileCount: tiles.count)
                                }, moveEarlier: index > 0 ? { moveInHand(tile.id, to: index - 1) } : nil,
                                         moveLater: index + 1 < tiles.count ? { moveInHand(tile.id, to: index + 1) } : nil)
                            } else {
                                tileButton(tile, table: table, rackCellWidth: cellWidth,
                                           rackMelds: rackMelds)
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
        .background(boardStyle.tray, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(boardStyle.trayEdge.opacity(0.65))
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("手牌")
        .accessibilityIdentifier("table-rack")
    }

    private func drawSlot(_ tile: Tile?, table: TableState, rackCellWidth: CGFloat? = nil) -> some View {
        let cellWidth = rackCellWidth ?? TeaTheme.hitTarget
        let cellHeight = max(TeaTheme.hitTarget, RackTile.faceSize(for: rackCellWidth).height)
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: dealStage?.isDealing != true)) { time in
            let dealerTileLanded = table.lastDraw?.isOpeningDeal == true && dealStage?.dealerTileLanded(at: time.date) == true
            let visible = tile != nil && (opening == nil || dealerTileLanded) && !localDrawInFlight(table)
            drawnTileDock(tile, table: table, rackCellWidth: rackCellWidth, cellWidth: cellWidth, cellHeight: cellHeight,
                          visible: visible)
        }
    }

    private func drawnTileDock(_ tile: Tile?, table: TableState, rackCellWidth: CGFloat?, cellWidth: CGFloat,
                               cellHeight: CGFloat, visible: Bool) -> some View {
        return VStack(spacing: 2) {
            Text(drawLabel(table))
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
                               rackMelds: availableRackMelds(table))
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

    private func drawLabel(_ table: TableState) -> String {
        table.lastDraw?.isOpeningDeal == true ? "坎门" : "刚摸到"
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
            playHaptic(.selection)
        }
        arrangementSelection = nil
    }

    private func availableRackMelds(_ table: TableState) -> [Move] {
        guard active, !arranging, opening == nil, session.moveStatus == nil,
              pendingThrow == nil, !localDrawInFlight(table) else { return [] }
        if let meldPreview {
            return meldPreview.highlightedMoves.filter(table.moves.contains)
        }
        // On your own turn, the rack stays in discard mode until you open a meld preview.
        return table.step == .claim ? table.moves.filter { $0.meld != nil } : []
    }

    private func tileButton(_ tile: Tile, table: TableState, rackCellWidth: CGFloat? = nil,
                            isDrawn: Bool = false, rackMelds: [Move]) -> some View {
        let playable = active && !arranging && opening == nil && session.moveStatus == nil && !localDrawInFlight(table)
        let options = meldOptions(for: tile, among: rackMelds, table: table)
        let canSwap = playable && robGoldChoice != nil && table.step == .opening && table.canSubmit(.discard(tile.id))
        let previewsMeld = !options.isEmpty && meldPreview?.selected != nil
        let canPlayOrdinaryTile = playable && !previewsOwnTurnMeld(table)
        let canDiscard = canPlayOrdinaryTile && !canSwap && options.isEmpty && table.moves.contains(.discard(tile.id))
        let canSelect = canSwap || !options.isEmpty || canDiscard || (canPlayOrdinaryTile && table.moves.contains(.replaceFlower(tile.id)))
        let swipeReady: (() -> Void)? = playsHaptics && (canDiscard || options.count == 1)
            ? { playHaptic(.selection) } : nil
        let meldAction: (label: String, perform: () -> Void)? = if options.isEmpty {
            nil
        } else {
            (options.count == 1 ? title(options[0], table: table) : "选择牌组", {
                handleRackMelds(options, from: table, commitWhenUnique: true)
            })
        }
        let selected = if canSwap {
            robGoldChoice?.tileID == tile.id
        } else if meldPreview?.selected != nil {
            previewsMeld
        } else {
            playable && tile.id == activeTile(table)
        }
        return RackTile(tile: tile, isGold: showsGoldIndicator && table.isGold(tile), isSelected: selected,
                        isDrawn: isDrawn, drawLabel: drawLabel(table),
                        canSelect: canSelect, canDiscard: canDiscard, rackCellWidth: rackCellWidth, select: {
            if canSwap {
                guard robGoldChoice?.tileID != tile.id, session.table?.canSubmit(.discard(tile.id)) == true else { return }
                robGoldChoice = .selected(tile.id)
                playHaptic(.selection)
                return
            }
            if !options.isEmpty {
                handleRackMelds(options, from: table, commitWhenUnique: false)
                return
            }
            meldPreview = nil
            guard selectedID != tile.id else { return }
            if reduceMotion { selectedID = tile.id }
            else { withAnimation(.easeOut(duration: 0.15)) { selectedID = tile.id } }
            playHaptic(.selection)
        }, discard: {
            send(.discard(tile.id))
        }, throwDiscard: { origin, released in
            send(.discard(tile.id), throwFrom: table.isGold(tile) ? origin : released)
        }, meldAction: meldAction, isRobGoldCandidate: canSwap, swipeReady: swipeReady)
    }

    private func meldOptions(for tile: Tile, among moves: [Move], table: TableState) -> [Move] {
        let exact = moves.filter { $0.meld?.ids.contains(tile.id) == true }
        guard !exact.isEmpty, table.step == .claim, meldPreview?.selected == nil else { return exact }
        // Identical copies are visually interchangeable before a group is selected.
        let matching = Set(table.hand.filter { $0.kind == tile.kind }.map(\.id)).union([tile.id])
        return moves.filter { $0.meld?.ids.contains(where: matching.contains) == true }
    }

    private func handleRackMelds(_ options: [Move], from source: TableState, commitWhenUnique: Bool) {
        guard active, !arranging, opening == nil, session.moveStatus == nil, pendingThrow == nil, let table = session.table,
              !localDrawInFlight(table), table.roundNumber == source.roundNumber, table.step == source.step,
              table.current == source.current, table.offeredTile == source.offeredTile,
              options.allSatisfy(table.moves.contains) else { return }
        let only = options.count == 1 ? options.first : nil
        if let only, commitWhenUnique {
            send(only)
        } else if only == nil || meldPreview?.selected != only {
            let visible = meldPreview.flatMap { preview in
                options.allSatisfy(preview.options.contains) ? preview.options : nil
            } ?? options
            showMeldPreview(MeldPreview(options: visible, selected: only))
        }
    }

    private func showMeldPreview(_ preview: MeldPreview) {
        guard meldPreview != preview else { return }
        meldPreview = preview
        playHaptic(.selection)
    }

    private func actions(_ table: TableState) -> some View {
        VStack(alignment: table.step == .claim || table.step == .opening ? .center : .trailing, spacing: 4) {
            if let robGoldChoice, let gold = table.gold, table.moves.contains(.win), table.step == .opening {
                robGoldConfirmation(robGoldChoice, gold: gold, table: table)
            } else if let meldPreview, meldPreview.options.allSatisfy(table.moves.contains) {
                meldConfirmation(meldPreview, table: table)
            }
            availableActions(table)
        }
        .disabled(!active || session.moveStatus != nil || pendingThrow != nil || localDrawInFlight(table))
    }

    private func availableActions(_ table: TableState) -> some View {
        let selected = previewsOwnTurnMeld(table) ? nil : activeTile(table)
        let replacesFlower = selected.map { table.moves.contains(.replaceFlower($0)) } ?? false
        let canWin = table.moves.contains(.win)
        let canPass = table.moves.contains(.pass)
        let melds = table.moves.filter { $0.meld != nil }

        return HStack(spacing: 4) {
            if canWin {
                if table.robGoldDiscardIDs != nil {
                    Button {
                        guard robGoldChoice == nil else { return }
                        robGoldChoice = .choosing
                        playHaptic(.selection)
                    } label: {
                        tableControlLabel("抢金", prominent: !session.paused, winning: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("选择一张手牌换成金牌")
                    .accessibilityIdentifier("declare-win")
                } else {
                    moveButton(.win, label: title(.win, table: table), table: table)
                }
            }
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

    private func robGoldConfirmation(_ choice: RobGoldChoice, gold: Tile, table: TableState) -> some View {
        let outgoing = choice.tileID.flatMap { id in
            table.drawn?.id == id ? table.drawn : table.hand.first { $0.id == id }
        }
        return HStack(spacing: 4) {
            closePreview("取消换牌", id: "cancel-rob-gold") { robGoldChoice = nil }
            HStack(spacing: 4) {
                if let outgoing {
                    swapTile("打出", tile: outgoing, gold: table.isGold(outgoing))
                } else {
                    Text("选一张手牌")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                swapTile("换入", tile: gold, gold: true)
            }
            .frame(maxWidth: .infinity)
            Button { if let outgoing { send(.discard(outgoing.id)) } } label: {
                tableControlLabel("确认抢金", prominent: outgoing != nil)
            }
            .buttonStyle(.plain)
            .disabled(outgoing == nil)
            .opacity(outgoing == nil ? 0.5 : 1)
            .accessibilityIdentifier("confirm-rob-gold")
        }
    }

    private func swapTile(_ label: String, tile: Tile, gold: Bool) -> some View {
        VStack(spacing: 2) {
            TileFace(kind: tile.kind, gold: gold)
                .frame(width: 17, height: 17 / TileFace.artworkAspectRatio)
            Text(label).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)\(tile.kind.spokenName)\(gold ? "金牌" : "")")
        .accessibilityIdentifier(label == "打出" ? "rob-gold-outgoing" : "rob-gold-incoming")
    }

    private func status(_ table: TableState) -> String {
        if let dealStage { return dealStage.title }
        if let result = table.result {
            return result.winner.map { "\(displayName($0, viewer: table.viewer, names: names)) · \(result.winTitle)" } ?? "流局"
        }
        if session.paused { return "等待牌友重新连接" }
        if let feedback = table.discardClaimFeedback { return feedback.message }
        if let moveStatus = session.moveStatus {
            switch moveStatus {
            case .sending: return "正在提交…"
            case .waitingForResolution: return "已提交，等待结算"
            }
        }
        if arranging { return arrangementSelection == nil ? "拖动手牌调整顺序" : "点一下要移到的位置" }
        if let robGoldChoice {
            return robGoldChoice.tileID == nil ? "轻点要换出的牌" : "确认换入金牌，或改选手牌"
        }
        if table.moves.contains(.win), table.step == .opening { return "可以抢金，也可以过" }
        if table.step == .opening { return "等待牌友决定是否抢金" }
        if let meldPreview {
            return meldPreview.selected == nil ? "轻点一个牌组" : "点确认，或上滑标记的手牌"
        }
        if table.step == .claim {
            if table.moves.contains(where: { $0.meld != nil }) { return "轻点或上滑高亮牌" }
            return table.moves.isEmpty ? "等待牌友要牌或过牌" : "可以要这张牌，也可以过"
        }
        let name = displayName(table.current, viewer: table.viewer, names: names)
        if let drawFlight, let drawCue, drawCue.seat == table.current {
            if drawCue.replacesFlowers { return "\(name)正在补花" }
            return drawFlight.fromReserve ? "\(name)正在补牌" : "\(name)正在摸牌"
        }
        if table.current == table.viewer { return "轮到你了" }
        return "轮到\(name)了"
    }

    @ViewBuilder
    private func meldControl(_ moves: [Move], label: String, table: TableState) -> some View {
        let options = moves.filter { $0.meld?.kind.actionLabel == label }
        if let first = options.first {
            Button {
                if moves.count == 1 { send(first) }
                else { showMeldPreview(MeldPreview(options: options, selected: options.count == 1 ? first : nil)) }
            } label: {
                tableControlLabel(label)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(moves.count == 1 ? title(first, table: table) : label)
            .accessibilityIdentifier("table-move-\(label)")
        }
    }

    private func meldConfirmation(_ preview: MeldPreview, table: TableState) -> some View {
        let showsKinds = Set(preview.options.compactMap { $0.meld?.kind.label }).count > 1
        let groups = HStack(spacing: 4) {
            ForEach(Array(preview.options.enumerated()), id: \.element) { index, option in
                let selected = option == preview.selected
                Button {
                    showMeldPreview(MeldPreview(options: preview.options, selected: option))
                } label: {
                    VStack(spacing: 1) {
                        meldTilesPreview(option, table: table)
                        if showsKinds, let kind = option.meld?.kind {
                            Text(kind.label).font(.caption2.weight(.semibold)).accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 3)
                    .frame(minWidth: TeaTheme.hitTarget, minHeight: TeaTheme.hitTarget)
                    .teaPanel(corner: 8, emphasized: selected)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option, table: table))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("meld-option-\(index)")
            }
        }

        return HStack(spacing: 4) {
            closePreview("关闭牌组选择", id: "cancel-meld-preview") { meldPreview = nil }
            ViewThatFits(in: .horizontal) {
                groups.fixedSize(horizontal: true, vertical: false)
                ScrollView(.horizontal) { groups }.scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity)
            .frame(height: TeaTheme.hitTarget)

            Button { if let move = preview.selected { send(move) } } label: {
                tableControlLabel("确认", prominent: preview.selected != nil)
            }
            .buttonStyle(.plain)
            .disabled(preview.selected == nil)
            .opacity(preview.selected == nil ? 0.5 : 1)
            .accessibilityLabel(preview.selected?.meld.map { "确认\($0.kind.label)" } ?? "确认牌组")
            .accessibilityIdentifier("confirm-meld")
        }
    }

    private func closePreview(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .frame(width: TeaTheme.hitTarget, height: TeaTheme.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func meldTilesPreview(_ move: Move, table: TableState) -> some View {
        HStack(spacing: 1) {
            ForEach(meldTiles(for: move, table: table)) { tile in
                TileFace(kind: tile.kind, gold: table.isGold(tile))
                    .frame(width: 16, height: 16 / TileFace.artworkAspectRatio)
                    .opacity(tile.id == table.offeredTile?.id ? 0.76 : 1)
                    .accessibilityHidden(true)
            }
        }
    }

    private func meldTiles(for move: Move, table: TableState) -> [Tile] {
        guard let meld = move.meld else { return [] }
        let rack = table.hand + [table.drawn].compactMap { $0 }
        let used = rack.filter { meld.ids.contains($0.id) }
        if meld.kind == .addedKong, let tile = used.first,
           let pung = table.players.first(where: { $0.seat == table.viewer })?.melds.first(where: {
               $0.kind == .pung && $0.tiles.first?.kind == tile.kind
           }) {
            return pung.tiles + used
        }
        let offered = table.step == .claim ? [table.offeredTile].compactMap { $0 } : []
        return (used + offered).sorted { $0.kind < $1.kind }
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
                                   winning: Bool = false, holdProgress: Bool? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        return Text(title)
            .font(winning ? .title3.weight(.bold) : .subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(prominent ? TeaTheme.brassInk : TeaTheme.ink)
            .padding(.horizontal, 5)
            .frame(minWidth: winning ? 64 : primary ? min(112, primaryControlWidth) : TeaTheme.hitTarget,
                   minHeight: winning ? 48 : TeaTheme.hitTarget)
            .background {
                ZStack {
                    shape.fill(prominent ? TeaTheme.brassFinish : TeaTheme.panelFinish)
                    if let holdProgress {
                        Rectangle().fill(TeaTheme.brass.opacity(0.24))
                            .scaleEffect(x: holdProgress ? 1 : 0, y: 1, anchor: .leading)
                            .environment(\.layoutDirection, .leftToRight)
                            .animation(holdProgress ? .linear(duration: OpeningSkipTarget.duration) : nil,
                                       value: holdProgress)
                            .clipShape(shape)
                    }
                }
            }
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
        guard let table = session.table, pendingThrow == nil, !localDrawInFlight(table), canSubmit(move, on: table) else { return }
        if table.step != .opening, case .discard(let id) = move,
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

    private func previewsOwnTurnMeld(_ table: TableState) -> Bool {
        table.step == .turn && meldPreview != nil
    }

    private func canSubmit(_ move: Move, on table: TableState) -> Bool {
        guard active, !arranging, opening == nil, session.moveStatus == nil, table.canSubmit(move) else { return false }
        if previewsOwnTurnMeld(table) {
            switch move {
            case .discard, .replaceFlower: return false
            default: break
            }
        }
        return true
    }

    private func commit(_ move: Move, throwFrom source: CGRect? = nil) {
        guard let table = session.table, canSubmit(move, on: table) else { return }
        if let source, !reduceMotion, case .discard(let id) = move {
            pendingThrow = PendingThrow(tileID: id, source: source)
        }
        guard session.submit(move) else {
            pendingThrow = nil
            return
        }
        meldPreview = nil
        robGoldChoice = nil
        selectedID = nil
    }

    private func resetDiscardMotion() {
        pendingThrow = nil
        discardFlight = nil
        claimFlight = nil
        presentedClaimFlightID = nil
    }
}

private struct OpeningSkipTarget: View {
    static let duration: TimeInterval = 0.8

    let size: CGSize
    @Binding var isHolding: Bool
    let skip: () -> Void
    @GestureState private var press = Press.idle

    private enum Press { case idle, holding, cancelled }

    var body: some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).updating($press) { value, press, _ in
                guard press != .cancelled else { return }
                let bounds = CGRect(origin: .zero, size: size)
                press = bounds.contains(value.location) ? .holding : .cancelled
            })
            .accessibilityHidden(true)
            .onChange(of: press == .holding) { _, holding in isHolding = holding }
            .onDisappear { isHolding = false }
            .task(id: press) {
                guard press == .holding else { return }
                do { try await Task.sleep(for: .seconds(Self.duration)) }
                catch { return }
                guard !Task.isCancelled, press == .holding else { return }
                skip()
            }
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

    var discardClaimLabel: String { meld?.kind.actionLabel ?? "胡" }
}

private extension DiscardClaimFeedback {
    var message: String {
        switch self {
        case .pending(let move):
            "已选\(move.discardClaimLabel)，等其他玩家回应"
        case .overridden(.win, _):
            "其他玩家优先胡牌"
        case .overridden(let move, let winner):
            "有人\(winner == .win ? "胡牌" : winner.discardClaimLabel)，这次没\(move.discardClaimLabel)成"
        }
    }
}
