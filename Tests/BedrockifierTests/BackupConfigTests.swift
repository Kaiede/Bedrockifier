import XCTest
@testable import Bedrockifier

final class BackupConfigTests: XCTestCase {
    func testScheduleInterval() {
        var schedule = BackupConfig.ScheduleConfig()

        XCTAssertEqual(try schedule.parseInterval(), nil)

        schedule.interval = "3h"
        XCTAssertEqual(try schedule.parseInterval(), 3 * 60.0 * 60.0)

        schedule.interval = "25M"
        XCTAssertEqual(try schedule.parseInterval(), 25 * 60.0)

        schedule.interval = "150s"
        XCTAssertEqual(try schedule.parseInterval(), 150.0)
    }

    static var allTests = [
        ("testScheduleInterval", testScheduleInterval),
    ]
}
