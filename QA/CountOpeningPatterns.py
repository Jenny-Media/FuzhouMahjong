"""Count physical opening racks without replacement or simulated play.

Run from the repo root with python3 QA/CountOpeningPatterns.py. The printed
numerators are used by FuzhouOpeningOdds. Each count vector is included once,
even if it has several valid decompositions.
"""

from collections import namedtuple
from math import comb, prod


# Five bits per rank let us add groups even when a wildcard takes a rank above
# four copies. Only physical tiles are limited to four copies per rank.
RANKS = tuple(1 << (5 * rank) for rank in range(9))
MELDS = tuple(3 * rank for rank in RANKS) + tuple(
    sum(RANKS[start:start + 3]) for start in range(7)
)
COPIES = tuple(comb(4, count) for count in range(5))
Weights = namedtuple("Weights", "total missing_rank")


def rank_counts(shape):
    return tuple((shape >> (5 * rank)) & 31 for rank in range(9))


def physical_weights(shapes):
    """Weight each rank vector by the number of ways to choose actual copies."""
    for shape in shapes:
        counts = rank_counts(shape)
        if max(counts) <= 4:
            yield shape, counts, prod(COPIES[count] for count in counts)


def weights(shapes):
    total = missing_rank = 0
    for _, counts, ways in physical_weights(shapes):
        total += ways
        # Sum over the nine possible gold ranks in this suit. Natural tiles
        # cannot have the gold rank, since all drawn copies count as wildcards.
        missing_rank += counts.count(0) * ways
    return Weights(total, missing_rank)


def remove_one(shapes):
    return {shape - rank for shape in shapes for rank in RANKS if shape & (31 * rank)}


def suit_allocations():
    for first in range(6):
        for second in range(6 - first):
            yield first, second, 5 - first - second


def count_patterns():
    meld_shapes = [{0}]
    for _ in range(5):
        meld_shapes.append({shape + meld for shape in meld_shapes[-1] for meld in MELDS})
    paired_shapes = [{shape + 2 * rank for shape in shapes for rank in RANKS} for shapes in meld_shapes]
    complete_melds = [weights(shapes) for shapes in meld_shapes]
    one_short = [weights(remove_one(shapes)) for shapes in meld_shapes]
    paired = [weights(shapes) for shapes in paired_shapes]
    allocations = tuple(suit_allocations())

    # In a natural win exactly one suit has a tile count congruent to two mod
    # three. Fix it as the first suit and then count the three choices of suit.
    rob_gold = 3 * sum(
        paired[a].total * complete_melds[b].total * complete_melds[c].total
        for a, b, c in allocations
    )

    # A gold pair uses two of the three copies. When all three are held, one
    # wildcard is left, and exactly one suit needs it to complete its melds.
    pair_suited = 3 * sum(
        complete_melds[a].missing_rank * complete_melds[b].total * complete_melds[c].total
        for a, b, c in allocations
    ) + sum(
        (one_short[a].missing_rank * complete_melds[b].total
         + 2 * complete_melds[a].missing_rank * one_short[b].total) * complete_melds[c].total
        for a, b, c in allocations
    )
    pair_honor = 3 * sum(
        (complete_melds[a].total + one_short[a].total)
        * complete_melds[b].total * complete_melds[c].total
        for a, b, c in allocations
    )

    # When face-value flush scoring applies, the same natural decomposition
    # must be able to use the marked rank as the pair.
    face_value_conflicts = 0
    for gold_count, naturals in ((2, meld_shapes[5]), (3, remove_one(meld_shapes[5]))):
        for shape, counts, ways in physical_weights(naturals):
            for rank, count in zip(RANKS, counts):
                if (count == 0 and shape + gold_count * rank in paired_shapes[5]
                        and shape + (gold_count - 2) * rank not in meld_shapes[5]):
                    face_value_conflicts += comb(3, gold_count) * ways

    flush_face_value = 3 * paired[5].total
    flush_suited = flush_honor = 0
    shapes = paired_shapes[5]
    for gold_count in range(4):
        total, missing_rank = weights(shapes)
        ways_to_draw_gold = comb(3, gold_count)
        flush_suited += ways_to_draw_gold * (18 * total + missing_rank)
        flush_honor += ways_to_draw_gold * 3 * total
        if gold_count < 3:
            shapes = remove_one(shapes)

    return {
        "robGold": rob_gold,
        "pairSuitedSumOverNineRanks": pair_suited,
        "faceValuePairSuitedSumOverNineRanks": pair_suited - face_value_conflicts,
        "pairHonor": pair_honor,
        "faceValueFlush": flush_face_value,
        "wildcardFlushSuitedSumOverNineRanks": flush_suited,
        "wildcardFlushHonor": flush_honor,
    }


if __name__ == "__main__":
    for pattern, count in count_patterns().items():
        print(f"{pattern} = {count:_}")
