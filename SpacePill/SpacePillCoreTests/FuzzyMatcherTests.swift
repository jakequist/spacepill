import XCTest
@testable import SpacePillCore

final class FuzzyMatcherTests: XCTestCase {

    // MARK: - Subsequence hits and misses

    func testMatchesContiguousSubstring() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "ocs", in: "Docs"))
    }

    func testMatchesScatteredSubsequence() {
        let match = FuzzyMatcher.match(query: "dcs", in: "Docs")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.positions, [0, 2, 3])
    }

    func testRejectsCharactersOutOfOrder() {
        XCTAssertNil(FuzzyMatcher.match(query: "scd", in: "Docs"))
    }

    func testRejectsCharactersNotPresent() {
        XCTAssertNil(FuzzyMatcher.match(query: "dcx", in: "Docs"))
    }

    func testRejectsQueryLongerThanTarget() {
        XCTAssertNil(FuzzyMatcher.match(query: "documents", in: "Docs"))
    }

    func testRejectsRepeatedCharacterWithoutEnoughOccurrences() {
        XCTAssertNil(FuzzyMatcher.match(query: "ddd", in: "Docs Dir"))
        XCTAssertNotNil(FuzzyMatcher.match(query: "dd", in: "Docs Dir"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(FuzzyMatcher.matches(query: "DCS", in: "docs"))
        XCTAssertTrue(FuzzyMatcher.matches(query: "dcs", in: "DOCS"))
    }

    func testEmptyQueryMatchesEverythingNeutrally() {
        let match = FuzzyMatcher.match(query: "", in: "Docs")
        XCTAssertEqual(match?.positions, [])
        XCTAssertEqual(match?.score, 0)
        XCTAssertEqual(match?.boundaryHits, 0)
        XCTAssertEqual(FuzzyMatcher.match(query: "   ", in: "Docs")?.positions, [])
    }

    func testEmptyTargetOnlyMatchesEmptyQuery() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "", in: ""))
        XCTAssertNil(FuzzyMatcher.match(query: "a", in: ""))
    }

    // MARK: - Unicode and diacritics

    func testDiacriticInsensitiveInBothDirections() {
        XCTAssertTrue(FuzzyMatcher.matches(query: "cafe", in: "Café"))
        XCTAssertTrue(FuzzyMatcher.matches(query: "café", in: "Cafe"))
        XCTAssertTrue(FuzzyMatcher.matches(query: "naive", in: "Naïve"))
    }

    func testDecomposedAndPrecomposedFormsAgree() {
        let precomposed = "Café"                    // U+00E9
        let decomposed = "Cafe\u{0301}"             // e + combining acute
        XCTAssertTrue(FuzzyMatcher.matches(query: "cafe", in: decomposed))
        XCTAssertTrue(FuzzyMatcher.matches(query: decomposed, in: precomposed))
        XCTAssertEqual(FuzzyMatcher.match(query: "caf", in: decomposed)?.positions, [0, 1, 2])
    }

    func testNonLatinScriptsMatch() {
        XCTAssertTrue(FuzzyMatcher.matches(query: "рбт", in: "Работа"))
        XCTAssertNil(FuzzyMatcher.match(query: "xyz", in: "Работа"))
    }

    func testEmojiCountsAsOneCharacter() {
        // Grapheme clusters, not UTF-16 units: the flag is a single position.
        let match = FuzzyMatcher.match(query: "ab", in: "a🇬🇧b")
        XCTAssertEqual(match?.positions, [0, 2])
        XCTAssertEqual(match?.targetLength, 3)
    }

    // MARK: - Alignment choice

    func testPrefersBoundaryAlignmentWhenSeveralArePossible() {
        // Both `d`s can serve; the one starting "Docs" is the better story.
        let match = FuzzyMatcher.match(query: "d", in: "Old Docs")
        XCTAssertEqual(match?.positions, [4])
        XCTAssertEqual(match?.boundaryHits, 1)
    }

    func testPrefersContiguousAlignmentOverScattered() {
        // "oo" could be threaded as 1+3, 1+4 or 3+4; the adjacent pair wins.
        let match = FuzzyMatcher.match(query: "oo", in: "xoxoo")
        XCTAssertEqual(match?.positions, [3, 4])
        XCTAssertEqual(match?.longestRun, 2)
    }

    func testDetectsExactAndPrefixMatches() {
        let exact = FuzzyMatcher.match(query: "docs", in: "Docs")
        XCTAssertEqual(exact?.isExactMatch, true)
        XCTAssertEqual(exact?.isPrefixMatch, true)

        let prefix = FuzzyMatcher.match(query: "doc", in: "Documents")
        XCTAssertEqual(prefix?.isExactMatch, false)
        XCTAssertEqual(prefix?.isPrefixMatch, true)

        let scattered = FuzzyMatcher.match(query: "dcs", in: "Docs")
        XCTAssertEqual(scattered?.isExactMatch, false)
        XCTAssertEqual(scattered?.isPrefixMatch, false)
    }

    func testExactMatchIgnoresCaseAndDiacritics() {
        XCTAssertEqual(FuzzyMatcher.match(query: "cafe", in: "CAFÉ")?.isExactMatch, true)
    }

    func testCamelCaseCountsAsABoundary() {
        let match = FuzzyMatcher.match(query: "dr", in: "DocReview")
        XCTAssertEqual(match?.positions, [0, 3])
        XCTAssertEqual(match?.boundaryHits, 2)
    }

    func testSeparatorsCountAsBoundaries() {
        XCTAssertEqual(FuzzyMatcher.match(query: "dr", in: "doc-review")?.boundaryHits, 2)
        XCTAssertEqual(FuzzyMatcher.match(query: "dr", in: "doc_review")?.boundaryHits, 2)
        XCTAssertEqual(FuzzyMatcher.match(query: "dr", in: "doc review")?.boundaryHits, 2)
    }

    // MARK: - rankedBefore

    func testRankedBeforePrefersExactThenPrefix() {
        let exact = FuzzyMatcher.match(query: "docs", in: "Docs")!
        let prefix = FuzzyMatcher.match(query: "docs", in: "Docs Archive")!
        XCTAssertEqual(exact.rankedBefore(prefix), true)
        XCTAssertEqual(prefix.rankedBefore(exact), false)
    }

    func testRankedBeforePrefersPrefixOverBoundaryHits() {
        let prefix = FuzzyMatcher.match(query: "doc", in: "Doc Review")!
        let boundaries = FuzzyMatcher.match(query: "doc", in: "Deep Ocean Craft")!
        XCTAssertEqual(boundaries.boundaryHits, 3)
        XCTAssertGreaterThan(boundaries.boundaryHits, prefix.boundaryHits)
        XCTAssertEqual(prefix.rankedBefore(boundaries), true)
    }

    func testRankedBeforePrefersBoundaryHitsOverContiguity() {
        let boundaries = FuzzyMatcher.match(query: "dc", in: "Dev Centre")!
        let contiguous = FuzzyMatcher.match(query: "dc", in: "Xdc")!
        XCTAssertEqual(boundaries.boundaryHits, 2)
        XCTAssertEqual(contiguous.longestRun, 2)
        XCTAssertEqual(boundaries.rankedBefore(contiguous), true)
    }

    func testRankedBeforePrefersContiguityOverEarlierPosition() {
        // Same length, no boundaries in play: the unbroken run wins even though
        // the other match starts earlier.
        let scattered = FuzzyMatcher.match(query: "ab", in: "xaxbx")!
        let contiguous = FuzzyMatcher.match(query: "ab", in: "xxxab")!
        XCTAssertEqual(scattered.firstPosition, 1)
        XCTAssertEqual(contiguous.firstPosition, 3)
        XCTAssertEqual(contiguous.rankedBefore(scattered), true)
    }

    func testRankedBeforePrefersEarlierPositionOverShorterTarget() {
        let early = FuzzyMatcher.match(query: "ab", in: "xabxxxxxxx")!
        let late = FuzzyMatcher.match(query: "ab", in: "xxxab")!
        XCTAssertEqual(early.rankedBefore(late), true)
    }

    func testRankedBeforeFallsBackToShorterTarget() {
        let short = FuzzyMatcher.match(query: "ab", in: "abc")!
        let long = FuzzyMatcher.match(query: "ab", in: "abcdef")!
        XCTAssertEqual(short.rankedBefore(long), true)
    }

    func testRankedBeforeReturnsNilForIndistinguishableMatches() {
        let left = FuzzyMatcher.match(query: "ab", in: "abc")!
        let right = FuzzyMatcher.match(query: "ab", in: "abd")!
        XCTAssertNil(left.rankedBefore(right))
    }
}
