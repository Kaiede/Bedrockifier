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

// Originally written for https://github.com/Kaiede/RPiLight
// Changes:
// - Scheduling in this version only supports hours and minutes

import Foundation

public struct DayTime: Codable {
    enum DecodeError: Error {
        case unableToParse
    }

    enum EncodeError: Error {
        case unableToGetDate
    }

    internal static let Components: Set<Calendar.Component> = [.calendar, .timeZone, .hour, .minute, .second]

    public internal(set) var dateComponents: DateComponents

    private static let Formatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.calendar = Calendar.current
        return dateFormatter
    }()

    public init(from date: Date, calendar: Calendar = Calendar.current) {
        self.dateComponents = calendar.dateComponents(DayTime.Components, from: date)
    }

    public init(_ components: DateComponents) {
        self.dateComponents = components.asTimeOfDay()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedString = try container.decode(String.self)
        guard let parsedTime = DayTime.Formatter.date(from: decodedString) else {
            throw DecodeError.unableToParse
        }
        dateComponents = Calendar.current.dateComponents(DayTime.Components, from: parsedTime)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let tempDate = self.calcNextDate(after: Date()) else {
            throw EncodeError.unableToGetDate
        }
        let encodedString = DayTime.Formatter.string(from: tempDate)
        try container.encode(encodedString)
    }
}

extension DayTime: Equatable {
    public static func == (lhs: DayTime, rhs: DayTime) -> Bool {
        return lhs.dateComponents == rhs.dateComponents
    }
}

extension DayTime: CustomStringConvertible {
    public var description: String {
        return self.dateComponents.description
    }
}

extension DayTime: CustomDebugStringConvertible {
    public var debugDescription: String {
        return self.dateComponents.debugDescription
    }
}

// MARK: Wrapper for DateComponent Access

public extension DayTime {
    var hour: Int? { return dateComponents.hour }
    var minute: Int? { return dateComponents.minute }
    var second: Int? { return dateComponents.second }
}

public extension DayTime {
    func calcNextDate(after date: Date, direction: Calendar.SearchDirection = .forward) -> Date? {
        let calendar = self.dateComponents.calendar ?? Calendar.current
        return calendar.nextDate(
            after: date,
            matching: self.dateComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: direction)
    }
}

// MARK: Internal Helper Functions

fileprivate extension DateComponents {
    func asTimeOfDay() -> DateComponents {
        return DateComponents(calendar: self.calendar,
                              timeZone: self.timeZone,
                              hour: self.hour,
                              minute: self.minute,
                              second: self.second,
                              nanosecond: self.nanosecond)
    }
}
