import XCTest
@testable import SpacePillCore

/// Stand-in for `QuickSwitchView.MatchItem`: the two fields the ranking uses.
private struct Space {
    let index: Int
    let label: String?

    var displayName: String { SpaceSearch.displayName(index: index, label: label) }
}

private func rank(_ spaces: [Space], _ query: String) -> [Int] {
    SpaceSearch.rank(spaces, query: query, index: { $0.index }, displayName: { $0.displayName })
        .map(\.index)
}

final class SpaceSearchTests: XCTestCase {

    /// Roughly the machine this was developed on: a few labelled Spaces among
    /// unlabelled ones.
    private let spaces = [
        Space(index: 1, label: nil),
        Space(index: 2, label: "Email"),
        Space(index: 3, label: "Code"),
        Space(index: 4, label: "Docs"),
        Space(index: 5, label: nil),
        Space(index: 6, label: nil)
    ]

    // MARK: - Display names

    func testDisplayNameFallsBackToSpaceN() {
        XCTAssertEqual(SpaceSearch.displayName(index: 7, label: nil), "Space 7")
        XCTAssertEqual(SpaceSearch.displayName(index: 7, label: ""), "Space 7")
        XCTAssertEqual(SpaceSearch.displayName(index: 7, label: "   "), "Space 7")
        XCTAssertEqual(SpaceSearch.displayName(index: 7, label: "Docs"), "Docs")
    }

    func testUnlabelledSpacesMatchTheStringTheUserSees() {
        // "Space 5" is on screen, so it has to be searchable.
        XCTAssertEqual(rank(spaces, "spc"), [1, 5, 6])
        XCTAssertEqual(rank(spaces, "space 5"), [5])
    }

    // MARK: - Fuzzy behaviour

    func testFuzzyQueryFindsDocs() {
        XCTAssertEqual(rank(spaces, "dcs").first, 4)
    }

    func testQueryIsCaseAndDiacriticInsensitive() {
        let accented = [Space(index: 1, label: "Café"), Space(index: 2, label: "Code")]
        XCTAssertEqual(rank(accented, "CAFE"), [1])
        XCTAssertEqual(rank(accented, "café"), [1])
    }

    func testNonMatchingQueryReturnsNothing() {
        XCTAssertEqual(rank(spaces, "zzz"), [])
    }

    func testEmptyQueryReturnsEverythingInIndexOrder() {
        XCTAssertEqual(rank(spaces, ""), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(rank(spaces, "   "), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(rank(spaces.reversed(), ""), [1, 2, 3, 4, 5, 6])
    }

    // MARK: - Ranking

    func testExactBeatsPrefixBeatsScattered() {
        let candidates = [
            Space(index: 1, label: "Deep Ocean Craft"),  // scattered d-o-c
            Space(index: 2, label: "Documents"),         // prefix
            Space(index: 3, label: "Doc")                // exact
        ]
        XCTAssertEqual(rank(candidates, "doc"), [3, 2, 1])
    }

    func testWordBoundaryHitsBeatMidWordHits() {
        let candidates = [
            Space(index: 1, label: "Backend"),      // b...e mid-word
            Space(index: 2, label: "Build Errors")  // both on word starts
        ]
        XCTAssertEqual(rank(candidates, "be"), [2, 1])
    }

    func testShorterLabelWinsAllElseEqual() {
        // Both are prefix matches starting at 0; only the length differs.
        let candidates = [
            Space(index: 1, label: "Codebase Review"),
            Space(index: 2, label: "Code")
        ]
        XCTAssertEqual(rank(candidates, "cod"), [2, 1])
    }

    // MARK: - Index queries

    func testExactIndexMatchRanksFirst() {
        let candidates = [
            Space(index: 1, label: "3rd Draft"),  // starts with the digit
            Space(index: 2, label: "Trio 3"),
            Space(index: 3, label: "Code")        // no "3" in the label at all
        ]
        XCTAssertEqual(rank(candidates, "3").first, 3)
    }

    func testIndexQueryStillMatchesLabelsAndDisplayNames() {
        XCTAssertEqual(rank(spaces, "1"), [1])
        // "Space 5" and "Space 6" both contain a digit; only 5 is an index hit.
        XCTAssertEqual(rank(spaces, "5"), [5])
    }

    func testMultiDigitIndexMatches() {
        let many = (1...12).map { Space(index: $0, label: nil) }
        XCTAssertEqual(rank(many, "12").first, 12)
        // Space 1 and Space 2 do not contain "12" in order, Space 12 does.
        XCTAssertEqual(rank(many, "12"), [12])
    }

    func testUnparseableDigitsDoNotCrashOrMatchAnIndex() {
        // Arabic-Indic three: `isNumber`, but not something Int() accepts.
        XCTAssertEqual(rank(spaces, "٣"), [])
    }

    func testNonIndexNumericQueryFallsBackToLabelMatching() {
        let candidates = [Space(index: 1, label: "Sprint 42")]
        XCTAssertEqual(rank(candidates, "42"), [1])
    }

    // MARK: - Determinism

    func testIdenticalLabelsFallBackToIndexOrder() {
        let candidates = [
            Space(index: 9, label: "Same"),
            Space(index: 2, label: "Same"),
            Space(index: 5, label: "Same")
        ]
        XCTAssertEqual(rank(candidates, "sm"), [2, 5, 9])
    }

    func testRankingIsStableAcrossRepeatedCalls() {
        let candidates = (1...40).map { Space(index: $0, label: "Space \($0 % 3)") }
        let first = rank(candidates, "sp")
        for _ in 0..<20 {
            XCTAssertEqual(rank(candidates, "sp"), first)
        }
    }

    func testInputOrderDoesNotChangeTheResult() {
        let candidates = [
            Space(index: 1, label: "Docs"),
            Space(index: 2, label: "Dev Console"),
            Space(index: 3, label: "Downloads Cache")
        ]
        XCTAssertEqual(rank(candidates, "dc"), rank(candidates.reversed(), "dc"))
    }
}
