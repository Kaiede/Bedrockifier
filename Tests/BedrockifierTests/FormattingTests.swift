import Foundation
import Testing
@testable import BedrockifierLib

@Suite struct FormattingTests {
    @Test func libraryFormatter() {
        let date = Date()
        print("\(Library.dateFormatter.string(from: date))")
    }

    @Test func dayTimeFormatter() {
        let date = Date()
        let dayTime = DayTime(from: date)
        print("Day Time: \(dayTime)")
    }
}
