import FuzhouCore
import SwiftUI

struct RuleGuide: View {
    let showsCloseButton: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var lesson = RuleLesson.turn
    @State private var claim = Claim.chow
    @State private var phase = 0
    @State private var replay = 0
    @AccessibilityFocusState private var lessonFocused: Bool

    init(startingAt lesson: RuleLesson = .turn, showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
        _lesson = State(initialValue: lesson)
    }

    var body: some View {
        let frames = lesson.frames(claim: claim)
        let frame = frames[reduceMotion ? frames.count - 1 : min(phase, frames.count - 1)]
        let wide = verticalSizeClass == .compact && !typeSize.isAccessibilitySize
        let layout = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(lesson.title).font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("rule-lesson-title")
                    .accessibilityFocused($lessonFocused)
                layout {
                    VStack(alignment: .trailing, spacing: 6) {
                        if lesson == .claims {
                            Picker("副露示范", selection: $claim) {
                                ForEach(Claim.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("rule-claim-picker")
                        }
                        RuleDiagram(frame: frame, description: frames[frames.count - 1].description)
                            .id(Example(lesson: lesson, claim: claim))
                        if !reduceMotion {
                            Button {
                                replay += 1
                            } label: {
                                Label("重播", systemImage: "arrow.counterclockwise")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .frame(minHeight: TeaTheme.hitTarget)
                            }
                            .accessibilityIdentifier("rule-replay")
                        }
                    }
                    .frame(maxWidth: wide ? 360 : .infinity)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(lesson.explanation(claim: claim))
                        Text(lesson.detail).font(.subheadline).foregroundStyle(TeaTheme.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(TeaTheme.gutter)
            .frame(maxWidth: 790)
            .frame(maxWidth: .infinity)
        }
        .id(lesson)
        .background(TeaTheme.canvas)
        .navigationTitle("玩法")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("目录", systemImage: "list.bullet") {
                    ForEach(RuleLesson.allCases, id: \.self) { page in
                        Button(page.title) { open(page) }
                    }
                }
                .accessibilityIdentifier("rule-contents")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { navigation }
        .modifier(HingeSafeContent())
        .task(id: Playback(example: Example(lesson: lesson, claim: claim), replay: replay,
                           reduceMotion: reduceMotion)) {
            phase = 0
            await Task.yield()
            guard !Task.isCancelled else { return }
            lessonFocused = true
            guard !reduceMotion else { return }
            for next in 1..<frames.count {
                do { try await Task.sleep(for: .milliseconds(760)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.38)) { phase = next }
            }
        }
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            if let previous = RuleLesson(rawValue: lesson.rawValue - 1) {
                Button("上一步") { open(previous) }
                    .buttonStyle(TeaButtonStyle(prominent: false))
                    .accessibilityIdentifier("rule-previous")
            }
            Spacer(minLength: 0)
            if let next = RuleLesson(rawValue: lesson.rawValue + 1) {
                Button("下一步") { open(next) }
                    .buttonStyle(TeaButtonStyle())
                    .accessibilityIdentifier("rule-next")
            } else {
                Button("完成") { dismiss() }
                    .buttonStyle(TeaButtonStyle())
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, TeaTheme.gutter)
        .padding(.vertical, 6)
        .background(TeaTheme.canvas)
        .overlay(alignment: .top) { Divider() }
    }

    private func open(_ page: RuleLesson) {
        lessonFocused = false
        phase = 0
        lesson = page
    }

    private struct Example: Hashable {
        let lesson: RuleLesson
        let claim: Claim
    }

    private struct Playback: Hashable {
        let example: Example
        let replay: Int
        let reduceMotion: Bool
    }
}

private struct RuleDiagram: View {
    let frame: RuleFrame
    let description: String
    @Namespace private var tileMotion

    var body: some View {
        GeometryReader { geometry in
            let width = min(28, max(12, (geometry.size.width - 20) / 10))
            VStack(spacing: 12) {
                lane(frame.top, width: width)
                lane(frame.bottom, width: width)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 160)
        .foregroundStyle(TeaTheme.feltInk)
        .modifier(Felt())
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("牌例")
        .accessibilityValue(description)
    }

    private func lane(_ lane: RuleLane, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lane.title).font(.caption.weight(.semibold)).lineLimit(1)
            HStack(spacing: 8) {
                ForEach(lane.groups.indices, id: \.self) { index in
                    HStack(spacing: 2) {
                        ForEach(lane.groups[index]) { tile in
                            Group {
                                if let kind = tile.kind {
                                    TileFace(kind: kind, gold: tile.gold, selected: tile.highlighted)
                                } else {
                                    TileBack()
                                }
                            }
                            .frame(width: width, height: width / TileFace.artworkAspectRatio)
                            .matchedGeometryEffect(id: tile.id, in: tileMotion)
                        }
                    }
                }
            }
            .frame(height: width / TileFace.artworkAspectRatio)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum RuleLesson: Int, CaseIterable, Identifiable {
    var id: Int { rawValue }
    case turn, flowers, claims, gold, winning

    var title: String {
        switch self {
        case .turn: "摸牌与出牌"
        case .flowers: "补花"
        case .claims: "吃、碰、杠"
        case .gold: "金牌与抢金"
        case .winning: "怎样胡牌"
        }
    }

    fileprivate func explanation(claim: Claim) -> String {
        switch self {
        case .turn: "每人开局有 16 张底牌。轮到你先摸一张，再选一张打出。标有「摸牌」的是刚摸到的牌。"
        case .flowers: "摸到风牌、中发白、花牌或季节牌时，通常会亮出这张牌，再从补牌区补一张。示范里先亮出梅，再补进三筒。"
        case .claims: claim.explanation
        case .gold: "开局翻出本局金牌。金牌能在胡牌时当作百搭。图中的二筒是金牌，可以代替七万，与六万、八万组成顺子。"
        case .winning: "凑齐五组牌和一对相同的牌就能胡。每组可以是同花色的三张连牌、三张相同的牌，或一组杠。"
        }
    }

    var detail: String {
        switch self {
        case .turn: "轻点一张手牌再按「出牌」，也可以直接把它向上滑出。"
        case .flowers: "这些牌如果也是金牌，可以留作百搭，也可以选「补花」。"
        case .claims: "多人要同一张弃牌时，胡牌优先，其次是碰和杠，最后是吃。"
        case .gold: "翻到梅兰菊竹或春夏秋冬时，这八种都是金牌。金牌不能用来吃、碰、杠，别人打出的金牌也不能接炮。打出金牌后本局只能自摸。开局若翻出的牌正好能让你胡，可以抢金。"
        case .winning: "已经亮出的副露也算一组。自己摸到完成胡牌的那张叫自摸。接别人刚打出的牌胡牌，叫接炮。"
        }
    }

    fileprivate func frames(claim: Claim) -> [RuleFrame] {
        switch self {
        case .turn:
            let hand = [RuleTile(1, .characters, 2), RuleTile(2, .characters, 3), RuleTile(3, .circles, 6)]
            let draw = RuleTile(4, .bamboo, 7, highlighted: true)
            return [
                RuleFrame(top: RuleLane("牌山", [RuleTile(4)]), bottom: RuleLane("手牌示例", hand)),
                RuleFrame(top: RuleLane("牌山"), bottom: RuleLane("摸到七条", hand + [draw])),
                RuleFrame(top: RuleLane("打出六筒", [hand[2]]),
                          bottom: RuleLane("留下刚摸的七条", Array(hand.prefix(2)) + [RuleTile(4, .bamboo, 7)]))
            ]
        case .flowers:
            let flower = RuleTile(1, .flower, 1, highlighted: true)
            let hand = [RuleTile(2, .characters, 7), RuleTile(3, .bamboo, 4)]
            return [
                RuleFrame(top: RuleLane("补牌区", [RuleTile(4)]), bottom: RuleLane("摸到梅", hand + [flower])),
                RuleFrame(top: RuleLane("亮出梅", [flower]),
                          bottom: RuleLane("补进三筒", hand + [RuleTile(4, .circles, 3, highlighted: true)]))
            ]
        case .claims:
            return claim.frames
        case .gold:
            let reveal = RuleTile(1, .circles, 2, gold: true)
            let wild = RuleTile(2, .circles, 2, gold: true)
            let six = RuleTile(3, .characters, 6)
            let eight = RuleTile(4, .characters, 8)
            return [
                RuleFrame(top: RuleLane("本局金牌", [reveal]), bottom: RuleLane("手牌示例", [six, eight, wild])),
                RuleFrame(top: RuleLane("本局金牌", [reveal]), bottom: RuleLane("金牌代替七万", [six, wild, eight]))
            ]
        case .winning:
            let top = RuleLane("三组顺子", groups: [
                [RuleTile(1, .characters, 1), RuleTile(2, .characters, 2), RuleTile(3, .characters, 3)],
                [RuleTile(4, .characters, 4), RuleTile(5, .characters, 5), RuleTile(6, .characters, 6)],
                [RuleTile(7, .circles, 7), RuleTile(8, .circles, 8), RuleTile(9, .circles, 9)]
            ])
            let groups = [
                [RuleTile(10, .bamboo, 3), RuleTile(11, .bamboo, 3), RuleTile(12, .bamboo, 3)],
                [RuleTile(13, .bamboo, 6), RuleTile(14, .bamboo, 7), RuleTile(15, .bamboo, 8)]
            ]
            let single = RuleTile(16, .characters, 9)
            let pair = [single, RuleTile(17, .characters, 9, highlighted: true)]
            return [
                RuleFrame(top: top, bottom: RuleLane("还差一张九万配成一对", groups: groups + [[single]])),
                RuleFrame(top: top, bottom: RuleLane("五组牌和一对齐了", groups: groups + [pair]))
            ]
        }
    }
}

private enum Claim: String, CaseIterable {
    case chow = "吃"
    case pung = "碰"
    case kong = "杠"

    var explanation: String {
        switch self {
        case .chow: "只能吃上家刚打出的牌。用手里的五万、七万，接上家的六万，凑成同花色的三张连牌。"
        case .pung: "手里有两张相同的牌时，可以碰任何一家刚打出的同一张牌，凑成三张。"
        case .kong: "用手里三张相同的牌，可以接别人的弃牌成明杠。手里已有四张可以暗杠，也可以用摸到的同一张牌给碰加杠。杠完再从补牌区补一张。"
        }
    }

    var frames: [RuleFrame] {
        let discard = RuleTile(1, .characters, 6, highlighted: true)
        let hand: [RuleTile]
        let meld: [RuleTile]
        switch self {
        case .chow:
            hand = [RuleTile(2, .characters, 5), RuleTile(3, .characters, 7)]
            meld = [hand[0], discard, hand[1]]
        case .pung:
            hand = [RuleTile(2, .characters, 6), RuleTile(3, .characters, 6)]
            meld = hand + [discard]
        case .kong:
            hand = [RuleTile(2, .characters, 6), RuleTile(3, .characters, 6), RuleTile(4, .characters, 6)]
            meld = hand + [discard]
        }
        var frames = [RuleFrame(top: RuleLane(self == .chow ? "上家打出六万" : "牌友打出六万", [discard]),
                                bottom: RuleLane("手牌示例", hand))]
        frames.append(RuleFrame(top: self == .kong ? RuleLane("补牌区", [RuleTile(5)]) : RuleLane("弃牌已接走"),
                                bottom: RuleLane("亮出这一组", meld)))
        if self == .kong {
            frames.append(RuleFrame(top: RuleLane("补进手牌", [RuleTile(5, .circles, 4, highlighted: true)]),
                                    bottom: RuleLane("亮出明杠", meld)))
        }
        return frames
    }
}

private struct RuleTile: Identifiable {
    let id: Int
    var kind: TileKind?
    var gold = false
    var highlighted = false

    init(_ id: Int) { self.id = id }

    init(_ id: Int, _ suit: Suit, _ rank: Int, gold: Bool = false, highlighted: Bool = false) {
        self.id = id
        self.kind = TileKind(suit, rank)
        self.gold = gold
        self.highlighted = highlighted
    }
}

private struct RuleLane {
    let title: String
    let groups: [[RuleTile]]

    init(_ title: String, _ tiles: [RuleTile] = []) {
        self.init(title, groups: [tiles])
    }

    init(_ title: String, groups: [[RuleTile]]) {
        self.title = title
        self.groups = groups
    }
}

private struct RuleFrame {
    let top: RuleLane
    let bottom: RuleLane

    var description: String {
        [top, bottom].map { lane in
            let tiles = lane.groups.map { group in
                group.compactMap { tile in
                    tile.kind.map { $0.spokenName + (tile.gold ? "金牌" : "") }
                }.joined(separator: "、")
            }.filter { !$0.isEmpty }.joined(separator: "，")
            return lane.title + "，" + tiles
        }.joined(separator: "。")
    }
}
