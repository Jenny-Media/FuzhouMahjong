import FuzhouCore
import SwiftUI

enum RuleOdds {
    static func rate(_ share: Double) -> String {
        if share == 0 { return "0%" }
        if share < 0.0001 {
            let racks = (1 / share).formatted(.number.notation(.compactName)
                .precision(.significantDigits(2)).locale(Locale(identifier: "zh_CN")))
            return "约 \(racks)分之一"
        }
        return "约 \(share.formatted(.percent.precision(.fractionLength(2))))"
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
    private var goldIndicators: FuzhouHouseRules.GoldIndicators { houseRules?.goldIndicators ?? .suitedOnly }
    private var odds: FuzhouOpeningOdds { .init(flush: flush, goldIndicators: goldIndicators) }

    var body: some View {
        if ruleset == .legacy {
            Text("原版规则的每项得分会列在「本局结算」里。")
                .padding(16).teaPanel()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                overviewCard
                patternCard
                openingGoldCard
                examplesCard
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("规则一览").font(.headline).foregroundStyle(TeaTheme.brass)
                .accessibilityAddTraits(.isHeader)
            Text(goldIndicators.explanation).accessibilityIdentifier("ruleset-gold-detail")
            Text(houseRules?.keepDealerOnDraw == true ? "庄家胡牌或流局，下一局都由庄家继续坐庄。" : "庄家胡牌继续坐庄，流局时由庄家的下家坐庄。")
            Text("接炮胡时\((houseRules?.discardPayment ?? .discarder).title)。")
            Text(flush == .disabled ? "抢金、三金倒和金雀有特殊加分。清一色按普通胡牌计分。"
                 : "抢金、三金倒、金雀和清一色有特殊加分。")
                .accessibilityIdentifier("ruleset-pattern-detail")
            Text(houseRules?.stackBonuses == true ? "一手牌符合多项特殊加分时，各项相加。" : "一手牌符合多项特殊加分时，只取最高的一项。")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .teaPanel()
    }

    private var patternCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("起手牌型概率")
                .font(.headline).foregroundStyle(TeaTheme.brass)
                .accessibilityAddTraits(.isHeader)
            Text("按一位玩家起手拿到的牌计算。抢金看补花后的 16 张加翻出的牌，其余牌型按补花后的 17 张随机牌计算。")
                .font(.footnote).foregroundStyle(TeaTheme.muted)
                .accessibilityIdentifier("rule-odds-method")
            ForEach([WinPattern.robGold, .threeGold, .goldenPair, .pureSuit]) { pattern in
                let chance = odds.probability(of: pattern)
                Divider()
                rateRow(pattern.title, detail: patternDetail(pattern), value: chance.map(RuleOdds.rate) ?? "不加分",
                        bonus: chance.map { _ in pattern.bonus })
                    .accessibilityIdentifier("rule-odds-\(pattern.rawValue)")
            }
            if flush != .disabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("清一色概率对照").font(.subheadline.weight(.semibold))
                    ForEach([FuzhouHouseRules.Flush.wildcard, .faceValue], id: \.self) { option in
                        let comparison = FuzhouOpeningOdds(flush: option, goldIndicators: goldIndicators)
                        if let chance = comparison.probability(of: .pureSuit) {
                            Text("\(option.title) · \(RuleOdds.rate(chance))")
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(TeaTheme.muted)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TeaTheme.feltDark, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityIdentifier("rule-odds-flush-comparison")
            }
            Text("整局的胡牌和流局机会还会随各家的打法变化。")
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
                    value: RuleOdds.rate(odds.atLeastTwoGoldInRack))
            Divider()
            rateRow("三张金", detail: "按补花后、第一张牌摸进来之前的 16 张起手牌计算。",
                    value: RuleOdds.rate(odds.threeGoldInRack))
            if goldIndicators.includesWinds {
                Divider()
                rateRow("翻风牌作金", detail: "翻出的金牌是东、南、西或北。", value: RuleOdds.rate(odds.windIndicatorChance))
            }
            if goldIndicators.includesDragons {
                Divider()
                rateRow("翻中发白作金", detail: "翻出的金牌是中、发或白。", value: RuleOdds.rate(odds.dragonIndicatorChance))
            }
            Text("翻出万、筒、条作金时，可用牌共 107 张，其中有 3 张金。" +
                 (goldIndicators == .suitedOnly ? "" : "翻出字牌作金时，可用牌共 111 张，其中也有 3 张金。"))
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
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .teaPanel()
    }

    private func patternDetail(_ pattern: WinPattern) -> String {
        switch pattern {
        case .robGold: "开局翻出的那张牌，按牌面就能帮你凑齐五组牌和一对将牌。"
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
