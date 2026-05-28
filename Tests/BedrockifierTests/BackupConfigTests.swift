import Testing
@testable import BedrockifierLib

@Suite struct BackupConfigTests {
    @Test func scheduleInterval() throws {
        var schedule = ScheduleConfig()

        #expect(try schedule.parseInterval() == nil)

        schedule.interval = "3h"
        #expect(try schedule.parseInterval() == 3 * 60.0 * 60.0)

        schedule.interval = "25M"
        #expect(try schedule.parseInterval() == 25 * 60.0)

        schedule.interval = "150s"
        #expect(try schedule.parseInterval() == 150.0)
    }
}
