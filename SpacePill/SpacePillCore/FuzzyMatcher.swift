import Foundation

/**
 * The outcome of matching a query against one target string.
 *
 * Everything the ranking needs is captured here rather than collapsed into a
 * single number, because "which of these two matches is better" is a
 * *lexicographic* question — an exact hit beats a prefix hit no matter how many
 * word boundaries the prefix hit happened to land on. `score` is only used to
 * choose between the different ways one query can be threaded through one
 * target; `rankedBefore(_:)` is what orders results against each other.
 */
public struct FuzzyMatch: Equatable {
    /// Character offsets in the target (not the folded form) that the query
    /// consumed, in order. Empty for an empty query.
    public let positions: [Int]

    /// Quality of this particular alignment. Comparable only within one target.
    public let score: Int

    /// The whole target, ignoring case and diacritics.
    public let isExactMatch: Bool

    /// The target begins with the query, ignoring case and diacritics.
    public let isPrefixMatch: Bool

    /// How many matched characters landed on a word or CamelCase boundary.
    public let boundaryHits: Int

    /// Longest run of adjacent matched characters.
    public let longestRun: Int

    /// Offset of the first matched character; 0 for an empty query.
    public let firstPosition: Int

    /// Character count of the target, used as a late tiebreak.
    public let targetLength: Int

    /**
     * Total ordering between two matches of the *same* query, best first.
     *
     * `nil` means the two are indistinguishable on every criterion, at which
     * point the caller must break the tie with something stable (SpacePill uses
     * the space index) or the list will jitter — `Array.sorted` is not a stable
     * sort.
     */
    public func rankedBefore(_ other: FuzzyMatch) -> Bool? {
        if isExactMatch != other.isExactMatch { return isExactMatch }
        if isPrefixMatch != other.isPrefixMatch { return isPrefixMatch }
        if boundaryHits != other.boundaryHits { return boundaryHits > other.boundaryHits }
        if longestRun != other.longestRun { return longestRun > other.longestRun }
        if firstPosition != other.firstPosition { return firstPosition < other.firstPosition }
        if targetLength != other.targetLength { return targetLength < other.targetLength }
        return nil
    }
}

/**
 * Subsequence ("fuzzy") matching in the spirit of a command palette.
 *
 * A query matches when its characters appear in the target in order but not
 * necessarily together, so `dcs` finds `Docs`. Comparison is case- and
 * diacritic-insensitive: `cafe` finds `Café`, and `Café` finds `Cafe`.
 *
 * There are usually several ways to thread a query through a target — in
 * `"Deep Docs"` the `d` of `dcs` can be either `D`. The alignment is chosen by a
 * memoised search that maximises `score`, whose weights are deliberately spread
 * far apart (1000 / 100 / 1) so that maximising the scalar also maximises the
 * criteria `FuzzyMatch.rankedBefore(_:)` cares about, in the same order.
 *
 * Pure Foundation on purpose: this target carries no AppKit, SwiftUI or SkyLight
 * dependency so it can be unit tested without a GUI session.
 */
public enum FuzzyMatcher {
    /// A matched character that starts a word, or a CamelCase hump.
    private static let boundaryBonus = 1_000

    /// A matched character immediately after the previous one.
    private static let contiguousBonus = 100

    /// Per-character penalty for matching late in the target, capped below one
    /// `contiguousBonus` so it can never outweigh an unbroken run.
    private static let maxLeadingPenalty = 90

    /**
     * Matches `query` against `target`.
     *
     * - Returns: `nil` when the query is not a subsequence of the target. An
     *   empty (or whitespace-only) query matches everything with a neutral
     *   result, which keeps "no query" from disturbing the caller's own order.
     */
    public static func match(query: String, in target: String) -> FuzzyMatch? {
        let targetCharacters = Array(target)
        let foldedTarget = targetCharacters.map(fold)
        let foldedQuery = Array(query.trimmingCharacters(in: .whitespacesAndNewlines)).map(fold)

        guard !foldedQuery.isEmpty else {
            return FuzzyMatch(positions: [],
                              score: 0,
                              isExactMatch: false,
                              isPrefixMatch: false,
                              boundaryHits: 0,
                              longestRun: 0,
                              firstPosition: 0,
                              targetLength: targetCharacters.count)
        }
        guard foldedQuery.count <= foldedTarget.count else { return nil }

        let boundaries = boundaryFlags(targetCharacters)

        struct Key: Hashable {
            let queryIndex: Int
            let targetIndex: Int
            /// Whether `targetIndex - 1` was consumed, which is the only thing
            /// the score needs from the path taken so far.
            let followsMatch: Bool
        }
        struct Alignment {
            let score: Int
            let positions: [Int]
        }

        var memo: [Key: Alignment?] = [:]

        func best(_ queryIndex: Int, _ targetIndex: Int, _ followsMatch: Bool) -> Alignment? {
            if queryIndex == foldedQuery.count { return Alignment(score: 0, positions: []) }
            // Not enough characters left to consume the rest of the query.
            if foldedTarget.count - targetIndex < foldedQuery.count - queryIndex { return nil }

            let key = Key(queryIndex: queryIndex, targetIndex: targetIndex, followsMatch: followsMatch)
            if let cached = memo[key] { return cached }

            var winner: Alignment?
            for position in targetIndex..<foldedTarget.count {
                guard foldedTarget[position] == foldedQuery[queryIndex] else { continue }
                guard let rest = best(queryIndex + 1, position + 1, true) else { continue }

                var score = rest.score
                if boundaries[position] { score += boundaryBonus }
                if followsMatch && position == targetIndex { score += contiguousBonus }
                score -= min(position, maxLeadingPenalty)

                if winner == nil || score > winner!.score {
                    winner = Alignment(score: score, positions: [position] + rest.positions)
                }
            }

            memo[key] = winner
            return winner
        }

        guard let alignment = best(0, 0, false) else { return nil }

        var boundaryHits = 0
        var longestRun = 1
        var currentRun = 1
        for (offset, position) in alignment.positions.enumerated() {
            if boundaries[position] { boundaryHits += 1 }
            if offset > 0 {
                currentRun = position == alignment.positions[offset - 1] + 1 ? currentRun + 1 : 1
                longestRun = max(longestRun, currentRun)
            }
        }

        return FuzzyMatch(
            positions: alignment.positions,
            score: alignment.score,
            isExactMatch: foldedQuery == foldedTarget,
            isPrefixMatch: foldedTarget.starts(with: foldedQuery),
            boundaryHits: boundaryHits,
            longestRun: longestRun,
            firstPosition: alignment.positions.first ?? 0,
            targetLength: targetCharacters.count
        )
    }

    /// Convenience for callers that only need the yes/no answer.
    public static func matches(query: String, in target: String) -> Bool {
        match(query: query, in: target) != nil
    }

    /**
     * Case- and diacritic-folded form of a single character.
     *
     * Folded per character rather than per string so that the folded array stays
     * index-aligned with the original — the boundary and position logic below
     * indexes into both. A fold that expands (`ß` → `ss`) stays in one slot and
     * simply compares unequal to a single `s`, which is the conservative answer.
     */
    private static func fold(_ character: Character) -> String {
        String(character)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
    }

    /**
     * Which offsets start a "word": the first character, anything after a
     * separator, and the upper-case half of a CamelCase hump.
     */
    private static func boundaryFlags(_ characters: [Character]) -> [Bool] {
        characters.enumerated().map { offset, character in
            guard offset > 0 else { return true }
            let previous = characters[offset - 1]
            if previous.isWhitespace || previous.isPunctuation || previous.isSymbol { return true }
            if character.isUppercase && (previous.isLowercase || previous.isNumber) { return true }
            if character.isNumber && !previous.isNumber { return true }
            return false
        }
    }
}
