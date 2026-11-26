import FuzhouCore
import SwiftUI
import UIKit

struct MeldGesturePractice: View {
    let lesson: GestureLesson

    private struct Choice: Identifiable {
        enum ID: String {
            case lowChow, highChow, pung, kong
        }

        let id: ID
        let title: String
        let used: [Tile]

        func tiles(with offered: Tile) -> [Tile] {
            (used + [offered]).sorted { $0.kind < $1.kind }
        }
    }

    private struct Sample {
        let offered: Tile
        let hand: [Tile]
        let starters: [Tile]
        let choices: [Choice]
        var replacement: Tile?
    }

    private enum Step: Equatable {
        case ready, choosing(Choice.ID?), pungClaimed, replacementDrawn, complete(Choice.ID)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.boardStyle) private var boardStyle
    @AppStorage("practice.haptics.enabled") private var hapticsEnabled = true
    @State private var step = Step.ready
    @State private var rackReset = 0

    private static let fives = Tile.fullSet.filter { $0.kind == TileKind(.circles, 5) }
    private static let filler = [tile(.characters, 8), tile(.bamboo, 9)]
    private static let chowSample: Sample = {
        let three = tile(.circles, 3)
        let four = tile(.circles, 4)
        let six = tile(.circles, 6)
        return Sample(offered: fives[0], hand: [three, four, six] + filler, starters: [four], choices: [
            Choice(id: .lowChow, title: "三四五", used: [three, four]),
            Choice(id: .highChow, title: "四五六", used: [four, six]),
        ])
    }()
    private static let kongSample: Sample = {
        let matches = Array(fives.dropFirst())
        return Sample(offered: fives[0], hand: matches + filler, starters: matches, choices: [
            Choice(id: .pung, title: "碰", used: Array(matches.prefix(2))),
            Choice(id: .kong, title: "明杠", used: matches),
        ], replacement: tile(.bamboo, 7))
    }()

    private var sample: Sample { lesson == .kong ? Self.kongSample : Self.chowSample }

    var body: some View {
        GesturePracticeLayout {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("gesture-practice-step")
                Text(instruction)
                    .font(.body)
                    .foregroundStyle(TeaTheme.muted)
                    .accessibilityIdentifier("gesture-practice-instruction")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } board: {
            GesturePracticeBoard(slotCount: sample.hand.count) {
                tableTiles
            } rack: { cellWidth in
                rack(cellWidth: cellWidth)
            }
            .id(rackReset)
        } actions: {
            actions
        }
        .navigationTitle(lesson.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("退出") { dismiss() }
                    .accessibilityIdentifier("gesture-practice-close")
            }
            if step != .ready {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重来", action: restart)
                        .accessibilityIdentifier("gesture-practice-restart")
                }
            }
        }
        .onChange(of: step) {
            if UIAccessibility.isVoiceOverRunning {
                AccessibilityNotification.Announcement("\(title)。\(instruction)").post()
            }
        }
    }

    private var title: String {
        switch step {
        case .ready: lesson == .kong ? "同一张牌可以碰，也可以杠" : "同一张牌有两种吃法"
        case .choosing: "选择一个牌组"
        case .pungClaimed: "碰牌成功"
        case .replacementDrawn: "明杠后补摸"
        case .complete(.kong): "补摸后出牌成功"
        case .complete: "吃牌成功"
        }
    }

    private var instruction: String {
        switch step {
        case .ready:
            lesson == .kong
                ? "牌友打出五筒。向上滑一张高亮的五筒，或点「选择牌组」。"
                : "上家打出五筒。向上滑高亮的四筒，或点「选择牌组」。"
        case .choosing(nil):
            lesson == .kong ? "点「碰」或「明杠」，看看各要用几张手牌。" : "点「三四五」或「四五六」，选出你想吃的顺子。"
        case .choosing(.some):
            "点「\(confirmationTitle)」，也可以上滑一张高亮的手牌。"
        case .pungClaimed:
            "碰用两张手牌，接着直接出牌。点「试试明杠」，看看杠后有什么变化。"
        case .replacementDrawn:
            "明杠用三张手牌，杠后会自动从牌尾补摸一张。向上滑刚摸到的七条，或点「出牌」。"
        case .complete(.kong):
            "你组成了四张五筒的明杠，补摸七条后打了出去。"
        case .complete:
            "你用两张手牌和上家打出的五筒组成了顺子。"
        }
    }

    @ViewBuilder
    private var tableTiles: some View {
        switch step {
        case .ready:
            GesturePracticeTileGroup(tiles: [sample.offered], label: "牌友打出的牌")
        case .choosing(let selected):
            let choices = HStack(spacing: 8) {
                ForEach(sample.choices) { choice in
                    choiceButton(choice, selected: choice.id == selected)
                }
            }
            ViewThatFits(in: .horizontal) {
                choices.fixedSize(horizontal: true, vertical: false)
                ScrollView(.horizontal) { choices }
                    .scrollIndicators(.hidden)
            }
        case .pungClaimed:
            claimedTiles(.pung, label: "碰到的牌")
        case .replacementDrawn:
            claimedTiles(.kong, label: "杠到的牌")
        case .complete(.kong):
            HStack(spacing: 12) {
                claimedTiles(.kong, label: "杠到的牌")
                if let replacement = sample.replacement {
                    GesturePracticeTileGroup(tiles: [replacement], label: "你打出的牌",
                                             identifier: "gesture-practice-replacement-discard")
                }
            }
        case .complete(let choice):
            claimedTiles(choice, label: "吃到的牌")
        }
    }

    private func claimedTiles(_ choice: Choice.ID, label: String) -> some View {
        let tiles = sample.choices.first { $0.id == choice }?.tiles(with: sample.offered) ?? []
        return GesturePracticeTileGroup(tiles: tiles, label: label)
    }

    private func choiceButton(_ choice: Choice, selected: Bool) -> some View {
        let tiles = choice.tiles(with: sample.offered)
        let hand = choice.used.map(\.kind.spokenName).joined(separator: "、")
        return Button {
            step = .choosing(choice.id)
        } label: {
            VStack(spacing: 4) {
                GesturePracticeTiles(tiles: tiles, width: 20, offeredTile: sample.offered)
                Text(choice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? TeaTheme.brass : TeaTheme.ink)
            }
            .padding(8)
            .frame(minWidth: TeaTheme.hitTarget, minHeight: TeaTheme.hitTarget)
            .teaPanel(corner: 10, emphasized: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityValue("牌友打出\(sample.offered.kind.spokenName)。手牌是\(hand)。")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("gesture-practice-choice-\(choice.id.rawValue)")
    }

    private var selectedChoice: Choice? {
        guard case .choosing(let id?) = step else { return nil }
        return sample.choices.first { $0.id == id }
    }

    private var confirmationTitle: String {
        switch selectedChoice?.id {
        case .pung: "确认碰牌"
        case .kong: "确认明杠"
        case .lowChow, .highChow: "确认吃牌"
        case nil: "确认"
        }
    }

    private var visibleHand: [Tile] {
        let claimed: Choice.ID
        switch step {
        case .ready, .choosing: return sample.hand
        case .pungClaimed: claimed = .pung
        case .replacementDrawn: claimed = .kong
        case .complete(let id): claimed = id
        }
        let used = sample.choices.first { $0.id == claimed }?.used ?? []
        return sample.hand.filter { !used.contains($0) }
    }

    private func rack(cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(visibleHand) { tile in
                handTile(tile, cellWidth: cellWidth)
            }
            if step == .replacementDrawn, let replacement = sample.replacement {
                Spacer(minLength: 6)
                RackTile(tile: replacement, isGold: false, isSelected: true, isDrawn: true, drawLabel: "杠后补摸",
                         canSelect: true, canDiscard: true, rackCellWidth: cellWidth, rackEdge: .trailing,
                         select: {}, discard: discardReplacement, throwDiscard: { _, _ in discardReplacement() })
            }
        }
        .frame(width: cellWidth * CGFloat(sample.hand.count), alignment: .leading)
        .padding(6)
        .background { RoundedRectangle(cornerRadius: 12).fill(boardStyle.tray) }
        .transformAnchorPreference(key: RackDragPreview.Key.self, value: .bounds) { $0.rackBounds = $1 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("练习手牌")
        .accessibilityIdentifier("gesture-practice-rack")
    }

    private func handTile(_ tile: Tile, cellWidth: CGFloat) -> RackTile {
        let choice = selectedChoice
        let showsChooser = step == .ready && sample.starters.contains(tile)
        let canCommit = choice?.used.contains(tile) == true
        let meldAction: (label: String, preview: [RackDragPreview.Face]?, perform: () -> Void)?
        if showsChooser {
            meldAction = ("选择牌组", nil, openChooser)
        } else if canCommit, let choice {
            let faces = choice.tiles(with: sample.offered).map {
                RackDragPreview.Face(tile: $0, isGold: false, fromRack: $0 != sample.offered)
            }
            meldAction = (confirmationTitle, faces, confirm)
        } else {
            meldAction = nil
        }
        let swipeReady: (() -> Void)? = hapticsEnabled && canCommit ? { UISelectionFeedbackGenerator().selectionChanged() } : nil
        return RackTile(tile: tile, isGold: false, isSelected: canCommit,
                        canSelect: showsChooser || canCommit, canDiscard: false, rackCellWidth: cellWidth,
                        select: { if showsChooser { openChooser() } }, discard: {},
                        meldAction: meldAction, swipeReady: swipeReady)
    }

    @ViewBuilder
    private var actions: some View {
        switch step {
        case .ready:
            actionButton("选择牌组", action: openChooser)
        case .choosing:
            HStack(spacing: 8) {
                Button("取消") { step = .ready }
                    .buttonStyle(TeaButtonStyle(prominent: false))
                    .accessibilityIdentifier("gesture-practice-cancel-choice")
                actionButton(confirmationTitle, action: confirm)
                    .disabled(selectedChoice == nil)
            }
        case .pungClaimed:
            actionButton("试试明杠", action: restart)
        case .replacementDrawn:
            actionButton("出牌", action: discardReplacement)
        case .complete:
            actionButton("完成") { dismiss() }
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(TeaButtonStyle())
        .accessibilityIdentifier("gesture-practice-action")
    }

    private func openChooser() {
        guard step == .ready else { return }
        step = .choosing(nil)
    }

    private func confirm() {
        guard let choice = selectedChoice else { return }
        switch choice.id {
        case .pung: step = .pungClaimed
        case .kong: step = .replacementDrawn
        case .lowChow, .highChow: step = .complete(choice.id)
        }
    }

    private func discardReplacement() {
        guard step == .replacementDrawn else { return }
        step = .complete(.kong)
    }

    private func restart() {
        rackReset += 1
        step = .ready
    }

    private static func tile(_ suit: Suit, _ rank: Int) -> Tile {
        let kind = TileKind(suit, rank)
        return Tile.fullSet.first { $0.kind == kind }!
    }
}
