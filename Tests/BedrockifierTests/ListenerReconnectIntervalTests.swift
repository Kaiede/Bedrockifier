import XCTest
@testable import Bedrockifier

final class ListenerReconnectIntervalTests: XCTestCase {
    func testParseListenerReconnectIntervalReturnsNilWhenUnset() throws {
        XCTAssertNil(try ListenerReconnectIntervalConfig.parse(nil))
    }

    func testParseListenerReconnectIntervalUsesConfiguredValue() throws {
        XCTAssertEqual(try ListenerReconnectIntervalConfig.parse("45s"), 45.0)
        XCTAssertEqual(try ListenerReconnectIntervalConfig.parse("2m"), 120.0)
    }

    func testParseListenerReconnectIntervalEnforcesMinimum() throws {
        XCTAssertEqual(try ListenerReconnectIntervalConfig.parse("1s"), 5.0)
        XCTAssertEqual(try ListenerReconnectIntervalConfig.parse("0"), 5.0)
    }

    func testParseListenerReconnectIntervalThrowsOnInvalidInput() {
        XCTAssertThrowsError(try ListenerReconnectIntervalConfig.parse("invalid-value"))
    }
}
