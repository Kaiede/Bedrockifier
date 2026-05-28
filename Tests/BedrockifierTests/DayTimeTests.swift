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

// swiftlint:disable trailing_comma
typealias JsonArray = [Any]

extension JSONDecoder {
    // Helper function for testing.
    // Enables using Arrays directly
    func decode<T>(_ type: T.Type, from array: JsonArray) throws -> T where T: Decodable {
        let data: Data = try JSONSerialization.data(withJSONObject: array)
        return try self.decode(type, from: data)
    }
}

@Suite struct DayTimeTests {
    @Test func dayTimeAccessors() {
        let testExpectations: [(String, Int, Int, Int)] = [
            ("08:00", 8, 0, 0),
            ("09:30", 9, 30, 0),
            ("21:45", 21, 45, 0)
        ]

        let testTimeZone = TimeZone(abbreviation: "UTC")!
        var testCalendar = Calendar(identifier: .gregorian)
        testCalendar.timeZone = testTimeZone

        for (timeString, hours, minutes, seconds) in testExpectations {
            let timeDate = DayTimeTests.timeFormatter.date(from: timeString)!
            let parsedTime = DayTime(from: timeDate, calendar: testCalendar)

            #expect(parsedTime.hour == hours)
            #expect(parsedTime.minute == minutes)
            #expect(parsedTime.second == seconds)
        }
    }

    @Test func dayTimeAccessorsDecoder() {
        let testExpectations: [(String, Int, Int, Int)] = [
            ("08:00", 8, 0, 0),
            ("09:30", 9, 30, 0),
            ("21:45", 21, 45, 0)
        ]

        for (timeString, hours, minutes, seconds) in testExpectations {
            let jsonData: JsonArray = [ timeString ]
            let decoder = JSONDecoder()
            do {
                let decodedTimeArray = try decoder.decode([DayTime].self, from: jsonData)
                guard let decodedTime = decodedTimeArray.first else {
                    Issue.record("Decode failed for: \(timeString)")
                    continue
                }

                #expect(decodedTime.hour == hours)
                #expect(decodedTime.minute == minutes)
                #expect(decodedTime.second == seconds)
                #expect(decodedTime.dateComponents.calendar == Calendar.current)
                #expect(decodedTime.dateComponents.timeZone == Calendar.current.timeZone)
            } catch {
                Issue.record("\(error)")
            }
        }
    }

    @Test func calcNextDate() {
        let dayInSeconds: TimeInterval = 86400
        let testExpectations: [(String, String, Calendar.SearchDirection)] = [
            ( "08:00", "08:00", .forward ),
            ( "08:00", "08:00", .backward ),
            ( "08:00", "08:30", .forward ),
            ( "08:00", "08:30", .backward )
        ]

        for (startString, targetString, searchDirection) in testExpectations {
            let startDate = DayTimeTests.timeFormatter.date(from: startString)!
            let targetDate = DayTimeTests.timeFormatter.date(from: targetString)!
            let targetTime = DayTime(from: targetDate)

            let calculatedDate = targetTime.calcNextDate(after: startDate, direction: searchDirection)!

            #expect(startDate != calculatedDate)
            switch searchDirection {
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
    }

    @Test func calcNextDateBoundaries() {
        let dayInSeconds: TimeInterval = 86400
        let testExpectations: [(String, String, Calendar.SearchDirection)] = [
            ( "31 Aug 09:00:00", "08:00", .forward ),
            ( "1 Sep 08:00:00", "09:00", .backward )
        ]

        for (startString, targetString, searchDirection) in testExpectations {
            let startDate = DayTimeTests.dateFormatter.date(from: startString)!
            let targetDate = DayTimeTests.timeFormatter.date(from: targetString)!
            let targetTime = DayTime(from: targetDate)

            let calculatedDate = targetTime.calcNextDate(after: startDate, direction: searchDirection)!

            #expect(startDate != calculatedDate)
            switch searchDirection {
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
    }

    @Test func calcNextDateDaylightSavings() {
        let testExpectations: [(String, String, Calendar.SearchDirection)] = [
            ( "2 Nov 2019 09:00:00", "3 Nov 2019 08:00:00", .forward ),
            ( "7 Mar 2020 09:00:00", "8 Mar 2020 08:00:00", .forward )
        ]

        for (startString, expectedString, searchDirection) in testExpectations {
            let startDate = DayTimeTests.daylightDateFormatter.date(from: startString)!
            let expectedDate = DayTimeTests.daylightDateFormatter.date(from: expectedString)!

            let targetTime = DayTime(from: expectedDate)
            let calculatedDate = targetTime.calcNextDate(after: startDate, direction: searchDirection)!

            #expect(targetTime == DayTime(from: calculatedDate))
            #expect(expectedDate == calculatedDate)
        }
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
