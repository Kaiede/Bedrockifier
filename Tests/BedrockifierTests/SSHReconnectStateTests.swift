import XCTest
@testable import Bedrockifier

final class SSHReconnectStateTests: XCTestCase {
    func testDisconnectStartsReconnectCycle() {
        var state = SSHReconnectState()

        XCTAssertTrue(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true))
    }

    func testDuplicateDisconnectDoesNotStartSecondReconnectCycle() {
        var state = SSHReconnectState()

        XCTAssertTrue(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true))
        XCTAssertFalse(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true))
    }

    func testReconnectCycleCanStartAgainAfterCompletion() {
        var state = SSHReconnectState()

        XCTAssertTrue(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true))
        state.reconnectCycleCompleted()
        XCTAssertTrue(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true))
    }

    func testDisconnectFromInactiveChannelDoesNotStartReconnectCycle() {
        var state = SSHReconnectState()

        XCTAssertFalse(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: false))
    }

    func testExplicitCloseSuppressesReconnectStart() {
        var state = SSHReconnectState()

        state.beginExplicitClose()
        XCTAssertFalse(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true))

        state.endExplicitClose()
        XCTAssertTrue(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true))
    }
}
