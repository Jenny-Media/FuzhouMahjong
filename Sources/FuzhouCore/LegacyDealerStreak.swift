/// Old archives increased the counter on every draw, even when the deal passed.
/// Only the current hand and cumulative seat balances survive in those archives.
struct LegacyDealerStreak {
    let dealer: Seat
    let dealerTurns: Int
    let priorHands: Int
    let continuation: Int
    let priorScores: [Int]
    let equalPayments: Bool

    var maximum: Int {
        guard continuation > 0, dealerTurns > 0 else { return continuation }
        let dealerWins = max(0, priorHands - dealerTurns)
        // A non-dealer win reset the streak even in the old format. Any such win
        // preceded the saved streak and used up one change of dealer.
        let possibleNonDealerWins = min(dealerTurns, max(0, priorHands - continuation))
        if dealerWins + possibleNonDealerWins <= 2 {
            return shortHistoryStreak(dealerWins: dealerWins, possibleNonDealerWins: possibleNonDealerWins)
        }
        let floor = equalPayments ? priorScores.min() ?? 0 : 0
        let possibleDealerWinners = min(dealerWins, dealerTurns + 1)
        let hasSeatWithoutWin = possibleDealerWinners + possibleNonDealerWins < Seat.allCases.count
        let otherWinners: Int
        if equalPayments, priorScores[dealer.id] == floor {
            // Equal payments put every seat that never won at the same minimum.
            // If the dealer at that minimum won, all four seats must have won.
            if hasSeatWithoutWin { return 0 }
            otherWinners = Seat.allCases.count - 1
        } else {
            // With equal payments a score above the minimum proves a prior win.
            // With a single payer only a positive balance proves one.
            let ahead = Seat.allCases.count { $0 != dealer && priorScores[$0.id] > floor }
            // If this seat won and still has no gain, somebody else must also have won.
            otherWinners = max(ahead, priorScores[dealer.id] <= 0 ? 1 : 0)
        }
        let otherDealerWins = max(0, otherWinners - possibleNonDealerWins)
        let limit = min(continuation, max(0, dealerWins - otherDealerWins))
        guard limit > 0 else { return 0 }
        func minimumWin(repeatsBack: Int) -> Int {
            FuzhouScoring.basePoints + FuzhouScoring.pointsPerDealerRepeat * (continuation - repeatsBack)
        }
        if !equalPayments {
            let opponents = Seat.allCases.filter { $0 != dealer }
            let knownOtherWinners = opponents.filter { priorScores[$0.id] > 0 }.count
            let losses = opponents.filter { priorScores[$0.id] < 0 }.count
            var minimumTotal = 0
            for repeats in 1...limit {
                let cheapest = minimumWin(repeatsBack: repeats)
                minimumTotal += cheapest
                let earlierWins = dealerWins + possibleNonDealerWins - repeats
                // Only a previous winner could have paid out more than their net loss.
                // If the other wins are all accounted for, every other seat only paid.
                let nonWinners = opponents.filter { seat in
                    let neverDealt = possibleNonDealerWins == 0 && seat.id > dealerTurns
                    return neverDealt || (earlierWins == knownOtherWinners && priorScores[seat.id] <= 0)
                }
                let knownLosses = nonWinners.map { -priorScores[$0.id] }
                let earlierLosses = knownLosses.filter { $0 > 0 && $0 < cheapest }
                let dealerLoss = minimumTotal - priorScores[dealer.id]
                if earlierWins == 0 {
                    let extra = losses > repeats ? 2 * cheapest : 0
                    if !earlierLosses.isEmpty || dealerLoss + extra > 0 { return repeats - 1 }
                } else if earlierLosses.count + (dealerLoss > 0 ? 1 : 0) > earlierWins {
                    // Too many different players paid for all earlier wins to be discards.
                    // Every nonwinner paid the same total on shared wins. Any remainder
                    // needs a separate discard, worth at least the base price.
                    var shared = knownLosses.min() ?? 0
                    if earlierLosses.contains(where: { $0 > shared && $0 - shared < FuzhouScoring.basePoints }),
                       let smallest = earlierLosses.min() {
                        shared = smallest - FuzhouScoring.basePoints
                    }
                    let singles = earlierLosses.count { $0 > shared } + (dealerLoss > shared ? 1 : 0)
                    if shared < FuzhouScoring.basePoints || 1 + singles > earlierWins { return repeats - 1 }
                }
            }
            return limit
        }
        guard hasSeatWithoutWin else { return limit }
        // Relative to a seat that never won, each win adds four times its face value.
        let wonPoints = priorScores.map { ($0 - floor) / Seat.allCases.count }
        let otherWinCapacity = Seat.allCases.filter { $0 != dealer }
            .reduce(0) { $0 + wonPoints[$1.id] / FuzhouScoring.basePoints }
        let winsToAccountFor = max(0, dealerWins - otherWinCapacity)
        var remaining = wonPoints[dealer.id]
        for repeats in 1...limit {
            // These are the last hands in the stored streak, even if it spans a dealer change.
            remaining -= minimumWin(repeatsBack: repeats)
            let earlierWins = max(0, winsToAccountFor - repeats)
            if remaining < earlierWins * FuzhouScoring.basePoints { return repeats - 1 }
        }
        return limit
    }

    /// With at most two paid hands, the four final balances can be checked against
    /// each possible settlement directly. The number of comparisons is independent of points.
    private func shortHistoryStreak(dealerWins: Int, possibleNonDealerWins: Int) -> Int {
        guard dealerWins > 0 else { return 0 }
        let base = FuzhouScoring.basePoints
        let increment = FuzhouScoring.pointsPerDealerRepeat
        let lastMinimum = base + increment * (continuation - 1)
        let lastPayments = payments(to: dealer)

        func matches(firstWinner: Seat, minimum: Int) -> Bool {
            payments(to: firstWinner).contains { first in
                lastPayments.contains { last in
                    matchesBalances(first: first, minimumFirst: minimum, last: last, minimumLast: lastMinimum)
                }
            }
        }

        if dealerWins == 2 {
            if continuation >= 2, matches(firstWinner: dealer, minimum: lastMinimum - increment) { return 2 }
            // Before the final win the only other paid hand was also a dealer win.
            // Check each dealer's earliest tenure, which has their smallest possible bonus.
            for turn in 0...min(dealerTurns, Seat.allCases.count - 1) {
                let earliestCounter = max(0, continuation - (priorHands - turn))
                if matches(firstWinner: Seat.east.advanced(turn), minimum: base + increment * earliestCounter) { return 1 }
            }
        } else {
            if lastPayments.contains(where: { $0.faceValue(for: priorScores).map { $0 >= lastMinimum } == true }) { return 1 }
            if possibleNonDealerWins > 0 {
                // The old counter restarted on the non-dealer win. Every earlier hand was a draw.
                let previousDealer = Seat.east.advanced(priorHands - continuation - 1)
                if Seat.allCases.contains(where: { $0 != previousDealer && matches(firstWinner: $0, minimum: base) }) { return 1 }
            }
        }
        return 0
    }

    private func payments(to winner: Seat) -> [Payment] {
        var sources: [Seat?] = [nil]
        if !equalPayments { sources += Seat.allCases.filter { $0 != winner } }
        return sources.map { Payment(winner: winner, source: $0) }
    }

    private struct Payment {
        let winner: Seat
        let shares: [Int]

        init(winner: Seat, source: Seat?) {
            self.winner = winner
            shares = Seat.allCases.map { RoundResult.shares(for: $0, winner: winner, source: source) }
        }

        func faceValue(for balances: [Int]) -> Int? {
            let face = balances[winner.id] / shares[winner.id]
            return Seat.allCases.allSatisfy { balances[$0.id] == face * shares[$0.id] } ? face : nil
        }
    }

    private func matchesBalances(first: Payment, minimumFirst: Int, last: Payment, minimumLast: Int) -> Bool {
        // Each balance is the sum of the two face values times that seat's payment shares.
        // Eliminate the first price using its winner's balance and one other seat's balance.
        let anchor = first.winner.id
        for seat in Seat.allCases where seat.id != anchor {
            let i = seat.id
            let divisor = first.shares[anchor] * last.shares[i] - first.shares[i] * last.shares[anchor]
            guard divisor != 0 else { continue }
            let numerator = first.shares[anchor] * priorScores[i] - first.shares[i] * priorScores[anchor]
            guard numerator.isMultiple(of: divisor) else { return false }
            let lastPrice = numerator / divisor
            guard lastPrice >= minimumLast else { return false }
            let remaining = Seat.allCases.map { priorScores[$0.id] - last.shares[$0.id] * lastPrice }
            return first.faceValue(for: remaining).map { $0 >= minimumFirst } == true
        }
        // Identical transfers add their prices. Opposite one-payer transfers can cancel.
        guard let netPrice = first.faceValue(for: priorScores) else { return false }
        return first.shares != last.shares || netPrice >= minimumFirst + minimumLast
    }
}
