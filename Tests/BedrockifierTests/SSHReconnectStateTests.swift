import Testing
@testable import BedrockifierLib

@Suite struct SSHReconnectStateTests {
    @Test func disconnectStartsReconnectCycle() {
        var state = SSHReconnectState()
        #expect(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true) == true)
    }

    @Test func duplicateDisconnectDoesNotStartSecondReconnectCycle() {
        var state = SSHReconnectState()
        #expect(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true) == true)
        #expect(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true) == false)
    }

    @Test func reconnectCycleCanStartAgainAfterCompletion() {
        var state = SSHReconnectState()
        #expect(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true) == true)
        state.reconnectCycleCompleted()
        #expect(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true) == true)
    }

    @Test func disconnectFromInactiveChannelDoesNotStartReconnectCycle() {
        var state = SSHReconnectState()
        #expect(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: false) == false)
    }

    @Test func explicitCloseSuppressesReconnectStart() {
        var state = SSHReconnectState()
        state.beginExplicitClose()
        #expect(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true) == false)
        state.endExplicitClose()
        #expect(state.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true) == true)
    }
}
