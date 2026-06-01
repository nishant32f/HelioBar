import XCTest
@testable import HelioCore

final class TokenStoringTests: XCTestCase {
    func test_roundTrips() throws {
        let store = InMemoryTokenStore()
        try store.save(ZeppCredentials(appToken: "abc", host: "h"))
        XCTAssertEqual(store.load(), ZeppCredentials(appToken: "abc", host: "h"))
    }

    func test_clearRemoves() throws {
        let store = InMemoryTokenStore()
        try store.save(ZeppCredentials(appToken: "abc", host: "h"))
        try store.clear()
        XCTAssertNil(store.load())
    }

    func test_loadNilWhenEmpty() {
        XCTAssertNil(InMemoryTokenStore().load())
    }
}
