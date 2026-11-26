import FuzhouCore
import SwiftUI

extension FuzhouRuleset {
    var title: String {
        switch self {
        case .pureSuit: "清一色加分"
        case .oldThree: "清一色不加分"
        case .legacy: "旧版存档规则"
        }
    }

    func displayTitle(houseRules: FuzhouHouseRules?) -> String {
        houseRules.map { $0.name.isEmpty ? "自定义规则预览" : $0.name } ?? title
    }

    var summary: String {
        switch self {
        case .pureSuit: "抢金、三金倒、金雀、清一色加分"
        case .oldThree: "抢金、三金倒、金雀加分"
        case .legacy: "早期单机牌局沿用的玩法"
        }
    }
}

struct RuleGuide: View {
    let showsCloseButton: Bool
    let ruleset: FuzhouRuleset
    let houseRules: FuzhouHouseRules?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var lesson = RuleLesson.turn
    @State private var claim = Claim.chow
    @State private var phase = 0
    @State private var replay = 0
    @State private var showsRulesetDetails = false
    @AccessibilityFocusState private var lessonFocused: Bool

    init(startingAt lesson: RuleLesson = .turn, showsCloseButton: Bool = false,
         ruleset: FuzhouRuleset = .pureSuit, houseRules: FuzhouHouseRules? = nil) {
        self.showsCloseButton = showsCloseButton
        self.ruleset = ruleset
        self.houseRules = houseRules
        _lesson = State(initialValue: lesson)
    }

    var body: some View {
        let frames = lesson.frames(claim: claim)
        let title = ruleset.displayTitle(houseRules: houseRules)
        let wide = verticalSizeClass == .compact && !typeSize.isAccessibilitySize
        let layout = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("规则 · \(title)")
                    .font(.caption.weight(.semibold)).foregroundStyle(TeaTheme.brass)
                    .accessibilityIdentifier("active-ruleset")
                Text(lesson.title).font(TeaTheme.display)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("rule-lesson-title")
                    .accessibilityFocused($lessonFocused)
                if !frames.isEmpty {
                    let frame = frames[reduceMotion ? frames.count - 1 : min(phase, frames.count - 1)]
                    layout {
                        VStack(alignment: .trailing, spacing: 6) {
                            if lesson == .claims {
                                Picker("吃、碰、杠示例", selection: $claim) {
                                    ForEach(Claim.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("rule-claim-picker")
                            }
                            RuleDiagram(frame: frame, description: frames[frames.count - 1].description)
                                .id(Example(lesson: lesson, claim: claim))
                            if !reduceMotion {
                                Button("重播", systemImage: "arrow.counterclockwise") { replay += 1 }
                                    .buttonStyle(TeaButtonStyle(prominent: false))
                                    .accessibilityIdentifier("rule-replay")
                            }
                        }
                        .frame(maxWidth: wide ? 360 : .infinity)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(lesson.explanation(claim: claim, ruleset: ruleset, indicators: houseRules?.goldIndicators ?? .suitedOnly))
                            Text(lesson.detail(for: ruleset, houseRules: houseRules))
                                .font(.subheadline).foregroundStyle(TeaTheme.muted)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .teaPanel()
                    }
                }
            }
            .padding(TeaTheme.gutter)
            .frame(maxWidth: 790)
            .frame(maxWidth: .infinity)
        }
        .id(lesson)
        .teaBackdrop()
        .navigationTitle("玩法教程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("玩法目录", systemImage: "list.bullet") {
                    ForEach(RuleLesson.allCases, id: \.self) { page in
                        Button(page.title) { open(page) }
                    }
                    Button("规则详情") { showsRulesetDetails = true }
                        .accessibilityIdentifier("tutorial-ruleset-details")
                }
                .accessibilityIdentifier("rule-contents")
            }
        }
        .navigationDestination(isPresented: $showsRulesetDetails) {
            RulesetDetailsPage(ruleset: ruleset, houseRules: houseRules)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { navigation }
        .modifier(HingeSafeContent())
        .task(id: Playback(example: Example(lesson: lesson, claim: claim), replay: replay,
                           reduceMotion: reduceMotion)) {
            phase = 0
            await Task.yield()
            guard !Task.isCancelled else { return }
            lessonFocused = true
            guard !reduceMotion, frames.count > 1 else { return }
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
                Button("规则详情") { showsRulesetDetails = true }
                    .buttonStyle(TeaButtonStyle())
                    .accessibilityIdentifier("rule-next")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, TeaTheme.gutter)
        .padding(.vertical, 6)
        .teaFooter()
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
        .modifier(Felt(inlaid: true))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("牌张示例")
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

    fileprivate func explanation(claim: Claim, ruleset: FuzhouRuleset, indicators: FuzhouHouseRules.GoldIndicators) -> String {
        switch self {
        case .turn:
            if ruleset == .legacy {
                "开局每人拿 16 张牌，补花、开金后由庄家先摸牌。平时轮到你时，通常是先摸一张，再打一张。"
            } else {
                "开局每人拿 16 张牌，庄家再拿一张，叫坎门。" +
                    (indicators.revealsBeforeFlowers ? "先开金，再补花。本局作金的字牌留在手中。" : "接着补花，再开金。") +
                    "平时轮到你时，通常是先摸一张，再打一张。"
            }
        case .flowers: "东南西北、中发白、梅兰竹菊、春夏秋冬通常都算花牌。摸到花牌时，先亮出来，再从牌尾补一张。图中亮出的是梅，补到的是三筒。"
        case .claims: claim.explanation
        case .gold: "开局翻一张牌来定本局的金牌。胡牌时，手里的金牌可以代替别的牌。图中用二筒金代替七万，组成六万、七万、八万的顺子。"
        case .winning: "普通胡牌需要凑齐五组牌和一对相同的牌。这一对叫将牌。每组可以是同一花色连着的三张牌（顺子）、三张相同的牌（刻子），或者一组杠。"
        }
    }

    func detail(for ruleset: FuzhouRuleset, houseRules: FuzhouHouseRules?) -> String {
        let indicators = houseRules?.goldIndicators ?? .suitedOnly
        return switch self {
        case .turn:
            "点一张牌，再点「出牌」，也可以直接向上滑出。刚摸到的牌还可以斜向桌面中央滑出。" + (houseRules.map { "\n\n\($0.summary)。" } ?? "")
        case .flowers:
            if ruleset == .legacy {
                "摸到也算金牌的花牌时，可以留作金牌，也可以选择补花。"
            } else {
                "开局从庄家开始轮流补花。如果补到的还是花牌，等其他玩家补完这一轮再补。" +
                    (indicators == .suitedOnly
                     ? "这套玩法共有 36 张花牌。" : "翻出字牌当金时，同样的字牌留作金牌。")
            }
        case .claims:
            "轻点高亮的手牌可以查看牌组。只有一种组合时，向上滑动高亮牌就能吃、碰或杠。有多种组合时，先选牌组。\n\n" +
                "多人要同一张牌时，先看胡牌，再看碰或杠，最后才是吃。" +
                (ruleset == .legacy ? "" : "有多人要胡时，金雀优先。同等优先级下，按出牌顺序取排在前面的一家。")
        case .gold:
            (ruleset == .legacy ? "翻到梅兰竹菊或春夏秋冬中的一张时，这八张花牌都算金牌。"
                    : indicators.explanation) +
                "\n\n手里的金牌不能用来吃、碰或杠。自己打出金牌后，这局只能自摸。别人打出的金牌也不能拿来胡牌。" +
                "\n\n开金后，如果翻出的牌能按牌面凑齐五组牌和一对将牌，就可以抢金。" +
                (ruleset == .legacy ? "庄家和闲家都把翻出的牌直接加进手牌。"
                 : "庄家要先选一张牌打出，再用翻出的牌补上。闲家直接加上翻出的牌。") +
                (indicators == .suitedOnly ? "" : "翻到字牌作金的这一局没有抢金。")
        case .winning:
            if ruleset == .legacy {
                "已经亮出的牌组也算在五组里。自己摸到胡牌的那张牌叫自摸。用别人刚打出的牌胡牌叫接炮。"
            } else {
                "已经亮出的牌组也算在五组里。自摸时，手里集齐三张金就能直接胡，这叫三金倒。胡牌时用两张金作将牌，叫金雀。点「规则详情」可查看各牌型的加分和计分示例。"
            }
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
                RuleFrame(top: top, bottom: RuleLane("凑齐五组牌和一对将牌", groups: groups + [pair]))
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
        case .chow: "上家是按出牌顺序排在你前面的一家。只能吃上家刚打出的牌。比如手里有五万和七万，上家打出六万，就可以吃成一组顺子。"
        case .pung: "手里有两张相同的牌，任意一家刚打出第三张时，你就可以碰。碰完亮出这组牌，再打一张。"
        case .kong: "手里有三张相同的牌，别人刚打出第四张，可以明杠。自己摸齐四张，可以暗杠。已经碰过一组，再摸到第四张，可以加杠。杠完从牌尾补一张，再出牌。"
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
        frames.append(RuleFrame(top: self == .kong ? RuleLane("从牌尾补一张", [RuleTile(5)]) : RuleLane("拿走打出的牌"),
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
