/*
 Bedrockifier

 Copyright (c) 2021 Adam Thayer
 Licensed under the MIT license, as follows:

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.)
 */

import Foundation
import Testing
@testable import Bedrockifier

typealias JsonArray = [Any]

extension JSONDecoder {
    // Helper function for testing.
    // Enables using Arrays directly
    func decode<T>(_ type: T.Type, from array: JsonArray) throws -> T where T: Decodable {
        let data: Data = try JSONSerialization.data(withJSONObject: array)
        return try self.decode(type, from: data)
    }
}

struct SearchExpectation {
    let start: String
    let target: String
    let direction: Calendar.SearchDirection
}

struct ComponentExpectation {
    let time: String
    let hours: Int
    let minutes: Int
    let seconds: Int
}

@Suite struct DayTimeTests {

    @Test(arguments: [
        ComponentExpectation(time: "08:00", hours: 8, minutes: 0, seconds: 0),
        ComponentExpectation(time: "09:30", hours: 9, minutes: 30, seconds: 0),
        ComponentExpectation(time: "21:45", hours: 21, minutes: 45, seconds: 0)
    ])
    func dayTimeAccessors(_ expectation: ComponentExpectation) {
        let testTimeZone = TimeZone(abbreviation: "UTC")!
        var testCalendar = Calendar(identifier: .gregorian)
        testCalendar.timeZone = testTimeZone

        let timeDate = DayTimeTests.timeFormatter.date(from: expectation.time)!
        let parsedTime = DayTime(from: timeDate, calendar: testCalendar)

        #expect(parsedTime.hour == expectation.hours)
        #expect(parsedTime.minute == expectation.minutes)
        #expect(parsedTime.second == expectation.seconds)
    }

    @Test(arguments: [
        ComponentExpectation(time: "08:00", hours: 8, minutes: 0, seconds: 0),
        ComponentExpectation(time: "09:30", hours: 9, minutes: 30, seconds: 0),
        ComponentExpectation(time: "21:45", hours: 21, minutes: 45, seconds: 0)
    ])
    func dayTimeAccessorsDecoder(_ expectation: ComponentExpectation) {
        let jsonData: JsonArray = [ expectation.time ]
        let decoder = JSONDecoder()
        do {
            let decodedTimeArray = try decoder.decode([DayTime].self, from: jsonData)
            guard let decodedTime = decodedTimeArray.first else {
                Issue.record("Decode failed for: \(expectation.time)")
                return
            }

            #expect(decodedTime.hour == expectation.hours)
            #expect(decodedTime.minute == expectation.minutes)
            #expect(decodedTime.second == expectation.seconds)
            #expect(decodedTime.dateComponents.calendar == Calendar.current)
            #expect(decodedTime.dateComponents.timeZone == Calendar.current.timeZone)
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test(arguments: [
        SearchExpectation(start: "08:00", target: "08:00", direction: .forward),
        SearchExpectation(start: "08:00", target: "08:00", direction: .backward),
        SearchExpectation(start: "08:00", target: "08:30", direction: .forward),
        SearchExpectation(start: "08:00", target: "08:30", direction: .backward)
    ])
    func calcNextDate(_ expectation: SearchExpectation) {
        let dayInSeconds: TimeInterval = 86400
        let startDate = DayTimeTests.timeFormatter.date(from: expectation.start)!
        let targetDate = DayTimeTests.timeFormatter.date(from: expectation.target)!
        let targetTime = DayTime(from: targetDate)

        let calculatedDate = targetTime.calcNextDate(after: startDate, direction: expectation.direction)!

        #expect(startDate != calculatedDate)
        switch expectation.direction {
        case .backward:
            #expect(calculatedDate < startDate)
            #expect(calculatedDate > startDate - (dayInSeconds * 2.0))
        case .forward:
            #expect(calculatedDate > startDate)
            #expect(calculatedDate < startDate + (dayInSeconds * 2.0))
        @unknown default:
            Issue.record("Unknown Search Direction")
        }

        #expect(targetTime == DayTime(from: calculatedDate))
        #expect(targetTime.dateComponents == Calendar.current.dateComponents(DayTime.components, from: calculatedDate))
    }

    @Test(arguments: [
        SearchExpectation(start: "31 Aug 09:00:00", target: "08:00", direction: .forward),
        SearchExpectation(start: "1 Sep 08:00:00", target: "09:00", direction: .backward)
    ])
    func calcNextDateBoundaries(_ expectation: SearchExpectation) {
        let dayInSeconds: TimeInterval = 86400
        let startDate = DayTimeTests.dateFormatter.date(from: expectation.start)!
        let targetDate = DayTimeTests.timeFormatter.date(from: expectation.target)!
        let targetTime = DayTime(from: targetDate)

        let calculatedDate = targetTime.calcNextDate(after: startDate, direction: expectation.direction)!

        #expect(startDate != calculatedDate)
        switch expectation.direction {
        case .backward:
            #expect(calculatedDate < startDate)
            #expect(calculatedDate > startDate - (dayInSeconds * 2.0))
        case .forward:
            #expect(calculatedDate > startDate)
            #expect(calculatedDate < startDate + (dayInSeconds * 2.0))
        @unknown default:
            Issue.record("Unknown Search Direction")
        }

        #expect(targetTime == DayTime(from: calculatedDate))
        #expect(targetTime.dateComponents == Calendar.current.dateComponents(DayTime.components, from: calculatedDate))
    }

    @Test(arguments: [
        SearchExpectation(start: "2 Nov 2019 09:00:00", target: "3 Nov 2019 08:00:00", direction: .forward),
        SearchExpectation(start: "7 Mar 2020 09:00:00", target: "8 Mar 2020 08:00:00", direction: .forward)
    ])
    func calcNextDateDaylightSavings(_ expectation: SearchExpectation) {
        let startDate = DayTimeTests.daylightDateFormatter.date(from: expectation.start)!
        let expectedDate = DayTimeTests.daylightDateFormatter.date(from: expectation.target)!

        let targetTime = DayTime(from: expectedDate)
        let calculatedDate = targetTime.calcNextDate(after: startDate, direction: expectation.direction)!

        #expect(targetTime == DayTime(from: calculatedDate))
        #expect(expectedDate == calculatedDate)
    }

    public private(set) static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM HH:mm:ss"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(abbreviation: "UTC")!
        return formatter
    }()

    public private(set) static var daylightDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy HH:mm:ss"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(abbreviation: "PDT")!
        return formatter
    }()

    private static let daylightTimeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.timeZone = TimeZone(abbreviation: "PDT")!
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        return dateFormatter
    }()

    private static let timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")!
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        return dateFormatter
    }()
}
