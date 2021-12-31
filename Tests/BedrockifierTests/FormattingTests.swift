import XCTest
@testable import Bedrockifier

final class FormattingTests: XCTestCase {
    func testLibraryFormatter() {
        let date = Date()
        print("\(Library.dateFormatter.string(from: date))")
    }

    func testDayTimeFormatter() {
        let date = Date()
        let dayTime = DayTime(from: date)
        print("Day Time: \(dayTime)")
    }
}
