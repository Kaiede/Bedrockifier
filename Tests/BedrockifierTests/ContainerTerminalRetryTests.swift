import XCTest
@testable import Bedrockifier

final class ContainerTerminalRetryTests: XCTestCase {
    private enum TestError: Error {
        case expectedFailure
    }

    func testRetrySaveQuerySucceedsOnThirdAttempt() async throws {
        var attempts = 0

        let result = try await retrySaveQuery(maxAttempts: 3) {
            attempts += 1
            return attempts == 3
        }

        XCTAssertTrue(result)
        XCTAssertEqual(attempts, 3)
    }

    func testRetrySaveQueryStopsAfterMaxAttempts() async throws {
        var attempts = 0

        let result = try await retrySaveQuery(maxAttempts: 3) {
            attempts += 1
            return false
        }

        XCTAssertFalse(result)
        XCTAssertEqual(attempts, 3)
    }

    func testRetrySaveQueryPropagatesErrors() async {
        var attempts = 0

        await XCTAssertThrowsErrorAsync(try await retrySaveQuery(maxAttempts: 3) {
            attempts += 1
            throw TestError.expectedFailure
        })

        XCTAssertEqual(attempts, 1)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {}
}
