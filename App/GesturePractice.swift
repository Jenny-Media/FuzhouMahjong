import FuzhouCore
import SwiftUI
import UIKit

struct GesturePractice: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(GestureLesson.allCases) { lesson in
                        NavigationLink(value: lesson) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lesson.title)
                                    Text(lesson.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(TeaTheme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(TeaButtonStyle(prominent: false, verticalPadding: 12))
                        .accessibilityIdentifier("gesture-practice-lesson-\(lesson.rawValue)")
                    }
                }
                .padding(TeaTheme.gutter)
                .frame(maxWidth: 510)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .modifier(HingeSafeContent())
            .teaBackdrop()
            .navigationTitle("手势练习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("gesture-practice-picker-close")
                }
            }
            .navigationDestination(for: GestureLesson.self) { lesson in
                switch lesson {
                case .basic: BasicGesturePractice()
                case .multipleChows, .kong: MeldGesturePractice(lesson: lesson)
                }
            }
        }
    }
}

enum GestureLesson: String, CaseIterable, Identifiable {
    case basic, multipleChows, kong

    var id: Self { self }

    var title: String {
        switch self {
        case .basic: "基础手势"
        case .multipleChows: "多种吃法"
        case .kong: "碰还是杠"
        }
    }

    var summary: String {
        switch self {
        case .basic: "出牌、预览与取消"
        case .multipleChows: "同一张牌有两种吃法"
        case .kong: "选择明杠，补摸后出牌"
        }
    }
}

struct GesturePracticeLayout<Instructions: View, Board: View, Actions: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let instructions: () -> Instructions
    @ViewBuilder let board: () -> Board
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 420 && geometry.size.height < 480
            let layout = sideBySide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            layout {
                Group {
                    if typeSize.isAccessibilitySize || (!sideBySide && geometry.size.height < 340) {
                        ScrollView { instructions() }
                            .scrollBounceBehavior(.basedOnSize)
                            .frame(maxHeight: sideBySide ? .infinity : geometry.size.height * 0.4)
                    } else {
                        instructions().fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: sideBySide ? min(280, geometry.size.width * 0.37) : .infinity,
                       alignment: .topLeading)
                VStack(spacing: 10) {
                    board()
                    actions()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(TeaTheme.gutter)
            .frame(maxWidth: sideBySide ? 900 : 510, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .modifier(HingeSafeContent())
        .teaBackdrop()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
    }
}

struct GesturePracticeBoard<TableTiles: View, Rack: View>: View {
    let slotCount: Int
    var showsDiscardArrow = false
    @ViewBuilder let tableTiles: () -> TableTiles
    @ViewBuilder let rack: (CGFloat) -> Rack

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = min(46, max(0, geometry.size.width - 28) / CGFloat(slotCount))
            VStack(spacing: 6) {
                tableTiles()
                    .frame(maxHeight: .infinity, alignment: showsDiscardArrow ? .bottom : .top)
                    .padding(.bottom, showsDiscardArrow ? 12 : 0)
                rack(cellWidth)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(Felt(gameTable: true))
            .overlayPreferenceValue(RackDragPreview.Key.self) { drag in
                if let preview = drag.preview {
                    RackDragOverlay(preview: preview, rackFaces: drag.rackFaces, rackBounds: drag.rackBounds,
                                    divisions: [])
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

struct GesturePracticeTileGroup: View {
    @Environment(\.boardStyle) private var boardStyle
    let tiles: [Tile]
    let label: String
    var offeredTile: Tile?
    var spokenValue: String?
    var identifier = "gesture-practice-table-tiles"

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(boardStyle.ink)
            GesturePracticeTiles(tiles: tiles, width: 32, offeredTile: offeredTile)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? tiles.map(\.kind.spokenName).joined(separator: "、"))
        .accessibilityIdentifier(identifier)
    }
}

struct GesturePracticeTiles: View {
    let tiles: [Tile]
    let width: CGFloat
    var offeredTile: Tile?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tiles) { tile in
                TileFace(kind: tile.kind, gold: false)
                    .frame(width: width, height: width / TileFace.artworkAspectRatio)
                    .overlay {
                        if tile == offeredTile {
                            RackDragPreview.tableTileOutline(width: width)
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BasicGesturePractice: View {
    private enum Step {
        case discard, discarded, previewChow, claimChow, complete

        var title: String {
            switch self {
            case .discard: "向上滑出一张牌"
            case .discarded: "出牌成功"
            case .previewChow: "先预览，再取消"
            case .claimChow: "现在试试吃牌"
            case .complete: "吃牌成功"
            }
        }

        var instruction: String {
            switch self {
            case .discard: "向上拖动高亮的七条，松手出牌。"
            case .discarded: "七条已经打到桌面。接下来试试用手牌吃牌。"
            case .previewChow: "慢慢向上拖动高亮牌一小段。看到三张牌后停一下，再松手取消。"
            case .claimChow: "预览已取消。再向上滑远一些，松手吃牌。"
            case .complete: "二筒、三筒、四筒组成了顺子。"
            }
        }

        var isChow: Bool { self == .previewChow || self == .claimChow }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.boardStyle) private var boardStyle
    @AppStorage("practice.haptics.enabled") private var hapticsEnabled = true
    @AppStorage("solo.gesturePracticeSeen") private var hasSeenGesturePractice = false
    @State private var step = Step.discard
    @State private var rackReset = 0
    @State private var selectedChow = false
    @State private var needsShorterDrag = false

    private static let discardTile = tile(.bamboo, 7)
    private static let offeredTile = tile(.circles, 2)
    private static let chowTiles = [tile(.circles, 3), tile(.circles, 4)]
    private static let hand = [tile(.characters, 5)] + chowTiles + [discardTile, tile(.bamboo, 9)]
    private static let chowFaces = [RackDragPreview.Face(tile: offeredTile, isGold: false, fromRack: false)]
        + chowTiles.map { RackDragPreview.Face(tile: $0, isGold: false) }
    private static let chowPreviewDescription = "牌友打出的牌是\(offeredTile.kind.spokenName)。"
        + "手牌是\(chowTiles.map(\.kind.spokenName).joined(separator: "、"))。"

    var body: some View {
        GesturePracticeLayout {
            instructions
        } board: {
            GesturePracticeBoard(slotCount: Self.hand.count, showsDiscardArrow: step == .discard) {
                tableTiles
            } rack: { cellWidth in
                rack(cellWidth: cellWidth)
            }
            .id(rackReset)
        } actions: {
            actionButton
        }
        .navigationTitle(GestureLesson.basic.title)
        .toolbar {
            if step != .complete {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出") { dismiss() }
                        .accessibilityIdentifier("gesture-practice-close")
                }
            }
            if step != .discard {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重来", action: restart)
                        .accessibilityIdentifier("gesture-practice-restart")
                }
            }
        }
        .onChange(of: step) { _, step in
            if UIAccessibility.isVoiceOverRunning {
                AccessibilityNotification.Announcement("\(step.title)。\(step.instruction)").post()
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("gesture-practice-step")
            Text(instruction)
                .font(.body)
                .foregroundStyle(TeaTheme.muted)
                .accessibilityIdentifier("gesture-practice-instruction")
            if step == .previewChow {
                Text("虚线标出牌友打出的牌。")
                    .font(.subheadline)
                    .foregroundStyle(TeaTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instruction: String {
        if step == .previewChow && selectedChow { return "点「取消预览」，手牌会留在原位。" }
        if step == .claimChow && selectedChow { return "点「确认吃牌」，把这组顺子摆到桌面上。" }
        if needsShorterDrag { return "刚才拖得太远或太快。慢慢向上拖一小段，看到三张牌后停一下，再松手。" }
        return step.instruction
    }

    @ViewBuilder
    private var tableTiles: some View {
        switch step {
        case .discard:
            Image(systemName: "arrow.up")
                .font(.title2.weight(.semibold))
                .foregroundStyle(boardStyle.ink)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        case .discarded:
            GesturePracticeTileGroup(tiles: [Self.discardTile], label: "你打出的牌")
        case .previewChow, .claimChow:
            if selectedChow {
                GesturePracticeTileGroup(tiles: [Self.offeredTile] + Self.chowTiles, label: "待确认的牌组",
                                         offeredTile: Self.offeredTile, spokenValue: Self.chowPreviewDescription)
            } else {
                GesturePracticeTileGroup(tiles: [Self.offeredTile], label: "牌友打出的牌")
            }
        case .complete:
            GesturePracticeTileGroup(tiles: [Self.offeredTile] + Self.chowTiles, label: "吃到的牌")
        }
    }

    private func rack(cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(visibleHand) { rackTile($0, cellWidth: cellWidth) }
        }
        .frame(width: cellWidth * CGFloat(Self.hand.count), alignment: .leading)
        .padding(6)
        .background { RoundedRectangle(cornerRadius: 12).fill(boardStyle.tray) }
        .transformAnchorPreference(key: RackDragPreview.Key.self, value: .bounds) { $0.rackBounds = $1 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("练习手牌")
        .accessibilityIdentifier("gesture-practice-rack")
    }

    private func rackTile(_ tile: Tile, cellWidth: CGFloat) -> RackTile {
        let canDiscard = step == .discard && tile == Self.discardTile
        let canDragChow = step.isChow && Self.chowTiles.contains(tile)
        let throwDiscard: ((CGRect, CGRect) -> Void)? = canDiscard ? { _, _ in discard() } : nil
        let meldAction: (label: String, preview: [RackDragPreview.Face]?, perform: () -> Void)? =
            canDragChow ? (label: actionTitle, preview: Self.chowFaces, perform: { releaseChowSwipe() }) : nil
        let onMeldDragCanceled: (() -> Void)? = canDragChow && step == .previewChow ? { previewCanceled() } : nil
        let onMeldAccessibilityAction: (() -> Void)? = canDragChow ? { performChowAction() } : nil
        let swipeReady: (() -> Void)? = hapticsEnabled ? { UISelectionFeedbackGenerator().selectionChanged() } : nil
        return RackTile(tile: tile, isGold: false, isSelected: canDiscard || (canDragChow && selectedChow),
                        canSelect: canDiscard || canDragChow, canDiscard: canDiscard, rackCellWidth: cellWidth,
                        select: { if canDragChow { showChowPreview() } }, discard: { discard() },
                        throwDiscard: throwDiscard, meldAction: meldAction,
                        onMeldDragCanceled: onMeldDragCanceled, onMeldAccessibilityAction: onMeldAccessibilityAction,
                        swipeReady: swipeReady)
    }

    private var visibleHand: [Tile] {
        switch step {
        case .discard: Self.hand
        case .discarded, .previewChow, .claimChow: Self.hand.filter { $0.id != Self.discardTile.id }
        case .complete: Self.hand.filter { $0.id != Self.discardTile.id && !Self.chowTiles.contains($0) }
        }
    }

    private var actionButton: some View {
        Button {
            switch step {
            case .discard: discard()
            case .discarded: step = .previewChow
            case .previewChow, .claimChow: performChowAction()
            case .complete: dismiss()
            }
        } label: {
            Text(actionTitle).frame(maxWidth: .infinity)
        }
        .buttonStyle(TeaButtonStyle(prominent: step == .discarded || step == .complete))
        .accessibilityIdentifier("gesture-practice-action")
    }

    private var actionTitle: String {
        switch step {
        case .discard: "出牌"
        case .discarded: "继续练习吃牌"
        case .previewChow: selectedChow ? "取消预览" : "预览牌组"
        case .claimChow: selectedChow ? "确认吃牌" : "吃牌"
        case .complete: "完成"
        }
    }

    private func discard() {
        guard step == .discard else { return }
        step = .discarded
    }

    private func previewCanceled() {
        guard step == .previewChow else { return }
        selectedChow = false
        needsShorterDrag = false
        step = .claimChow
    }

    private func performChowAction() {
        if step == .previewChow {
            if selectedChow {
                previewCanceled()
            } else {
                showChowPreview()
            }
        } else {
            claim()
        }
    }

    private func releaseChowSwipe() {
        if step == .previewChow {
            selectedChow = false
            needsShorterDrag = true
        } else {
            claim()
        }
    }

    private func showChowPreview() {
        needsShorterDrag = false
        selectedChow = true
        if UIAccessibility.isVoiceOverRunning {
            AccessibilityNotification.Announcement("\(Self.chowPreviewDescription)\(instruction)").post()
        }
    }

    private func claim() {
        guard step == .claimChow else { return }
        step = .complete
        hasSeenGesturePractice = true
    }

    private func restart() {
        rackReset += 1
        selectedChow = false
        needsShorterDrag = false
        step = .discard
    }

    private static func tile(_ suit: Suit, _ rank: Int) -> Tile {
        let kind = TileKind(suit, rank)
        return Tile.fullSet.first { $0.kind == kind }!
    }
}
