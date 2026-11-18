import FuzhouCore
import SwiftUI

enum RuleOdds {
    // Generated using QA/EstimateRuleOdds.swift and the modern 36-flower game engine.
    static let hands = 12_000
    static let draws = 272
    static let discardWins = 9_105
    private static let robGold = 2
    private static let threeGold = 225
    private static let goldenPair = 0
    private static let faceValueGoldenPair = 0
    private static let wildcardFlush = 4
    private static let faceValueFlush = 1

    // Inclusion of the first two specific gold copies in a uniformly drawn 16-tile rack.
    private static let twoSpecificGold = (16.0 / 107.0) * (15.0 / 106.0)
    static let openingThreeGold = twoSpecificGold * (14.0 / 105.0)
    static let openingAtLeastTwoGold = 3 * twoSpecificGold - 2 * openingThreeGold

    static func count(for pattern: WinPattern, flush: FuzhouHouseRules.Flush) -> Int? {
        switch pattern {
        case .robGold: robGold
        case .threeGold: threeGold
        case .goldenPair: flush == .faceValue ? faceValueGoldenPair : goldenPair
        case .pureSuit:
            switch flush {
            case .disabled: nil
            case .wildcard: wildcardFlush
            case .faceValue: faceValueFlush
            }
        }
    }

    static func rate(_ count: Int) -> String {
        if count == 0 { return "模拟中未出现" }
        return percentage(Double(count) / Double(hands))
    }

    static func percentage(_ share: Double) -> String {
        return "约 \(share.formatted(.percent.precision(.fractionLength(share < 0.01 ? 2 : 1))))"
    }
}

extension FuzhouRuleset {
    var defaultFlush: FuzhouHouseRules.Flush { self == .pureSuit ? .wildcard : .disabled }
}

extension FuzhouHouseRules.Flush {
    var explanation: String {
        switch self {
        case .disabled: "同一花色的牌凑齐五组和一对，也可以按普通牌型胡牌。"
        case .wildcard: "清一色的五组牌和将牌都要是同一花色，已亮出的牌组也算在内。例如，三筒金可以当三万，凑成万字清一色。"
        case .faceValue: "清一色的五组牌和将牌都要是同一花色。比如三筒是金，算清一色时仍当三筒。普通胡牌时，金仍可代牌。"
        }
    }
}

struct RuleReference: View {
    let ruleset: FuzhouRuleset
    let houseRules: FuzhouHouseRules?

    private var flush: FuzhouHouseRules.Flush { houseRules?.flush ?? ruleset.defaultFlush }

    var body: some View {
        if ruleset == .legacy {
            Text("原版规则的每项得分会列在「本局结算」里。模拟概率适用于加清一色、老三样和自定义玩法。")
                .padding(16).teaPanel()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                patternCard
                openingGoldCard
                examplesCard
            }
        }
    }

    private var patternCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("每局的参考概率")
                .font(.headline).foregroundStyle(TeaTheme.brass)
                .accessibilityAddTraits(.isHeader)
            Text("4 位电脑玩家模拟了 \(RuleOdds.hands.formatted()) 局。概率按全部牌局计算，包括流局。")
                .font(.footnote).foregroundStyle(TeaTheme.muted)
                .accessibilityIdentifier("rule-odds-method")
            ForEach([WinPattern.robGold, .threeGold, .goldenPair, .pureSuit]) { pattern in
                let count = RuleOdds.count(for: pattern, flush: flush)
                Divider()
                rateRow(pattern.title, detail: patternDetail(pattern), value: count.map(RuleOdds.rate) ?? "不加分",
                        bonus: count.map { _ in pattern.bonus })
                    .accessibilityIdentifier("rule-odds-\(pattern.rawValue)")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("清一色对照").font(.subheadline.weight(.semibold))
                ForEach([FuzhouHouseRules.Flush.wildcard, .faceValue], id: \.self) { option in
                    if let count = RuleOdds.count(for: .pureSuit, flush: option) {
                        Text("\(option.title) · \(RuleOdds.rate(count))（\(count) 局）")
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(TeaTheme.muted)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TeaTheme.feltDark, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityIdentifier("rule-odds-flush-comparison")

            Divider()
            rateRow("接炮胡", detail: "用别人刚打出的牌胡。打出这张牌的人就放炮了。", value: RuleOdds.rate(RuleOdds.discardWins))
            Divider()
            rateRow("流局", detail: "可摸的牌用完，仍然没人胡牌。", value: RuleOdds.rate(RuleOdds.draws))
            Text("每局按赢家符合的牌型统计。同一局可能计入多项。电脑只要能胡就会胡，实际概率会随打法变化。")
                .font(.footnote).foregroundStyle(TeaTheme.muted)
        }
        .padding(14)
        .teaPanel()
    }

    private var openingGoldCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("起手摸到金牌的概率").font(.headline).foregroundStyle(TeaTheme.brass)
                .accessibilityAddTraits(.isHeader)
            rateRow("至少两张金", detail: "金雀要用两张金作将牌，还要凑齐五组牌。",
                    value: RuleOdds.percentage(RuleOdds.openingAtLeastTwoGold))
            Divider()
            rateRow("三张金", detail: "这里算起手就有三张金。上面的三金倒统计的是整局的胡牌结果。",
                    value: RuleOdds.percentage(RuleOdds.openingThreeGold))
            Text("去掉翻出的金牌后，剩下 107 张万、筒、条，其中有三张金。概率按一位玩家随机拿 16 张计算。")
                .font(.footnote).foregroundStyle(TeaTheme.muted)
        }
        .padding(14)
        .teaPanel()
    }

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("计分示例").font(.headline).foregroundStyle(TeaTheme.brass)
                .accessibilityAddTraits(.isHeader)
            Text(RuleScoringExample.discard(payment: houseRules?.discardPayment ?? .discarder))
            Text(RuleScoringExample.bonuses(flush: flush, stacks: houseRules?.stackBonuses == true))
            Text("流局连庄决定下一局谁坐庄。点炮时谁付分、特殊加分是否叠加，只影响结算。一局里出现这些牌型的参考概率相同。")
                .font(.footnote).foregroundStyle(TeaTheme.muted)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .teaPanel()
    }

    private func patternDetail(_ pattern: WinPattern) -> String {
        switch pattern {
        case .robGold: "开局翻出的那张牌，正好能帮你凑齐五组牌和一对将牌。"
        case .threeGold: "自摸时手里有三张金，就能直接胡牌。"
        case .goldenPair: "凑齐五组牌，并用两张金作将牌。"
        case .pureSuit: flush.explanation
        }
    }

    private func rateRow(_ title: String, detail: String, value: String, bonus: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(TeaTheme.brass)
            }
            Text(detail).font(.footnote).foregroundStyle(TeaTheme.muted)
            if let bonus {
                Text("特殊加分 +\(bonus)").font(.caption.monospacedDigit()).foregroundStyle(TeaTheme.gain)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum RuleScoringExample {
    static func discard(payment: FuzhouHouseRules.DiscardPayment) -> String {
        if payment == .allOpponents { return "例如接炮胡按每份 20 分结算，其余三家各付 20 分，赢家得 60 分。" }
        return "例如接炮胡按每份 20 分结算，放炮的人付 20 分，赢家得 20 分。"
    }

    static func bonuses(flush: FuzhouHouseRules.Flush, stacks: Bool) -> String {
        let pair = WinPattern.goldenPair.bonus
        let pure = WinPattern.pureSuit.bonus
        if flush == .disabled { return "例如胡成金雀，可额外加 \(pair) 分。" }
        if stacks { return "例如同一手牌既是金雀又是清一色，两项合计加 \(pair + pure) 分。" }
        return "例如同一手牌既是金雀又是清一色，只取最高的一项，加 \(pure) 分。"
    }
}
