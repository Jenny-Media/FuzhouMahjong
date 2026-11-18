// From the repository root:
// swiftc -O Sources/FuzhouCore/{FuzhouMatch,FuzhouScoring,MatchTypes,Tile,WinningHand}.swift QA/EstimateRuleOdds.swift -o /tmp/fuzhou-rule-odds
// /tmp/fuzhou-rule-odds 12000

import Foundation

@main
struct EstimateRuleOdds {
    private struct SeededRandom: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }

    private struct Sample: Sendable {
        var counts: [String: Int] = [:]

        mutating func record(_ match: FuzhouMatch, faceValueRules: FuzhouHouseRules) {
            guard let result = match.result else { preconditionFailure("Hand did not settle") }
            guard let winner = result.winner else {
                counts["draw", default: 0] += 1
                return
            }
            guard let gold = match.gold, let kind = result.kind else { preconditionFailure("Missing settlement data") }
            let melds = match.table(for: winner).players[winner.id].melds
            let faceValue = FuzhouScoring.modern(hand: result.winningHand, melds: melds, flowers: [], gold: gold,
                                                 dealer: false, continuation: 0, kind: kind, ruleset: .pureSuit,
                                                 houseRules: faceValueRules)
            counts[kind == .discard ? "discard" : "otherWin", default: 0] += 1
            for pattern in result.patterns { counts[pattern.rawValue, default: 0] += 1 }
            for pattern in faceValue.patterns { counts["faceValue.\(pattern.rawValue)", default: 0] += 1 }
        }
    }

    static func main() async throws {
        let hands = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 12_000
        precondition(hands > 0)
        let workers = min(hands, ProcessInfo.processInfo.activeProcessorCount)
        let counts = await withTaskGroup(of: Sample.self, returning: [String: Int].self) { tasks in
            for worker in 0..<workers {
                tasks.addTask {
                    let faceValueRules = FuzhouHouseRules(name: "Face value", flush: .faceValue)
                    var sample = Sample()
                    for seed in stride(from: worker, to: hands, by: workers) {
                        var random = SeededRandom(state: UInt64(seed))
                        var match = FuzhouMatch(using: &random, ruleset: .pureSuit)
                        for _ in 0..<250 where match.result == nil {
                            guard let (seat, move) = match.nextComputerMove(excluding: []), match.apply(move, by: seat) else {
                                preconditionFailure("Computer move failed for seed \(seed)")
                            }
                        }
                        // Flush options change pattern scoring, so score the same completed hand with each interpretation.
                        sample.record(match, faceValueRules: faceValueRules)
                    }
                    return sample
                }
            }
            var totals = ["hands": hands]
            for await sample in tasks { totals.merge(sample.counts, uniquingKeysWith: +) }
            return totals
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(counts), as: UTF8.self))
    }
}
