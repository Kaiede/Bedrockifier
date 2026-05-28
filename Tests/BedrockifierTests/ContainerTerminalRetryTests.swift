import Testing
@testable import BedrockifierLib

@Suite struct ContainerTerminalRetryTests {
    private enum TestError: Error {
        case expectedFailure
    }

    @Test func retrySaveQuerySucceedsOnThirdAttempt() async throws {
        var attempts = 0

        let result = try await retrySaveQuery(maxAttempts: 3) {
            attempts += 1
            return attempts == 3
        }

        #expect(result)
        #expect(attempts == 3)
    }

    @Test func retrySaveQueryStopsAfterMaxAttempts() async throws {
        var attempts = 0

        let result = try await retrySaveQuery(maxAttempts: 3) {
            attempts += 1
            return false
        }

        #expect(!result)
        #expect(attempts == 3)
    }

    @Test func retrySaveQueryPropagatesErrors() async {
        var attempts = 0

        await #expect(throws: TestError.self) {
            _ = try await retrySaveQuery(maxAttempts: 3) {
                attempts += 1
                throw TestError.expectedFailure
            }
        }

        #expect(attempts == 1)
    }
}
