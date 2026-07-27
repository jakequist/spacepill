import XCTest
@testable import SpacePillCore

final class SpaceIdentityTests: XCTestCase {

    // MARK: - key(rawUUID:id64:)

    func testRealUUIDIsUsedVerbatim() {
        let uuid = "88C597ED-4FE2-4480-AEB9-95B4801D5302"
        XCTAssertEqual(SpaceIdentity.key(rawUUID: uuid, id64: 42), uuid)
    }

    func testEmptyUUIDFallsBackToId64() {
        let key = SpaceIdentity.key(rawUUID: "", id64: 7)
        XCTAssertEqual(key, "sp-id64:7")
        XCTAssertFalse(key.isEmpty)
    }

    func testNilUUIDFallsBackToId64() {
        XCTAssertEqual(SpaceIdentity.key(rawUUID: nil, id64: 7), "sp-id64:7")
    }

    func testDifferentEmptyUUIDSpacesGetDistinctKeys() {
        // The whole point: two spaces SkyLight can't identify must not collide
        // in the "" bucket any more.
        let a = SpaceIdentity.key(rawUUID: "", id64: 100)
        let b = SpaceIdentity.key(rawUUID: "", id64: 200)
        XCTAssertNotEqual(a, b)
    }

    func testSameId64IsStable() {
        XCTAssertEqual(SpaceIdentity.key(rawUUID: "", id64: 999),
                       SpaceIdentity.key(rawUUID: nil, id64: 999))
    }

    // MARK: - isSynthetic

    func testIsSyntheticForDerivedKeys() {
        XCTAssertTrue(SpaceIdentity.isSynthetic(SpaceIdentity.key(rawUUID: "", id64: 1)))
        XCTAssertTrue(SpaceIdentity.isSynthetic(SpaceIdentity.key(rawUUID: nil, id64: 1)))
    }

    func testIsNotSyntheticForRealUUID() {
        XCTAssertFalse(SpaceIdentity.isSynthetic("88C597ED-4FE2-4480-AEB9-95B4801D5302"))
        XCTAssertFalse(SpaceIdentity.isSynthetic(""))
    }

    func testSyntheticKeyCannotCollideWithRealUUID() {
        // Real SkyLight UUIDs never contain the prefix's colon-after-lowercase
        // shape, so a derived key is always distinguishable.
        let key = SpaceIdentity.key(rawUUID: "", id64: 12345)
        XCTAssertTrue(key.hasPrefix(SpaceIdentity.syntheticPrefix))
    }
}
