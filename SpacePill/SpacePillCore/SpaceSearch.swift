import Foundation

/**
 * Ranking of Spaces for the Quick Switch bar.
 *
 * Two things make this more than a call to `FuzzyMatcher`:
 *
 *  - **Spaces are addressable by number.** An all-digit query is first read as a
 *    space index, and an exact index hit is promoted above every label match —
 *    typing `3` must go to Space 3 even if some other Space is labelled `"3rd"`.
 *    Digit queries still match labels as well, they just rank below the index.
 *  - **Ties must not jitter.** `Array.sorted` is not stable, so once the match
 *    criteria are exhausted the space index breaks the tie. The same query
 *    always produces the same order.
 *
 * Pure logic, no AppKit/SwiftUI/SkyLight, so it is unit testable.
 */
public enum SpaceSearch {
    /**
     * What the user sees for a Space, and therefore what we match against:
     * its label, or `Space N` when it has none.
     */
    public static func displayName(index: Int, label: String?) -> String {
        guard let label = label, !label.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Space \(index)"
        }
        return label
    }

    /**
     * Filters and orders `items`, best match first.
     *
     * An empty (or whitespace-only) query returns everything in index order.
     *
     * - Parameters:
     *   - index: the 1-based space index, used for digit queries and tiebreaks.
     *   - displayName: the string the user sees; see `displayName(index:label:)`.
     */
    public static func rank<Item>(_ items: [Item],
                                  query: String,
                                  index: (Item) -> Int,
                                  displayName: (Item) -> String) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return items.sorted { index($0) < index($1) }
        }

        // `isNumber` is true for digits Int() cannot parse (Arabic-Indic, and
        // friends), so both have to agree before this is treated as an index.
        let queryIndex: Int? = trimmed.allSatisfy(\.isNumber) ? Int(trimmed) : nil

        var scored: [Scored<Item>] = []
        for item in items {
            let spaceIndex = index(item)
            let isIndexMatch = queryIndex != nil && queryIndex == spaceIndex
            let match = FuzzyMatcher.match(query: trimmed, in: displayName(item))
            guard match != nil || isIndexMatch else { continue }
            scored.append(Scored(item: item, index: spaceIndex, match: match, isIndexMatch: isIndexMatch))
        }

        return scored.sorted { lhs, rhs in
            if lhs.isIndexMatch != rhs.isIndexMatch { return lhs.isIndexMatch }
            switch (lhs.match, rhs.match) {
            case let (left?, right?):
                if let ordered = left.rankedBefore(right) { return ordered }
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                break
            }
            return lhs.index < rhs.index
        }.map(\.item)
    }
}

/// One candidate and how well it matched. Top level because a generic function
/// cannot nest a type that mentions its own type parameter.
private struct Scored<Item> {
    let item: Item
    let index: Int
    let match: FuzzyMatch?
    let isIndexMatch: Bool
}
