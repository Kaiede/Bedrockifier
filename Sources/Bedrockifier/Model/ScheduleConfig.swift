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

public struct ScheduleConfig: Codable {
    // Interval Based Schedules
    public var daily: DayTime?
    public var interval: String?
    public var startupDelay: String?

    // Event Based Schedules
    public var onPlayerLogin: Bool?
    public var onPlayerLogout: Bool?
    public var onLastLogout: Bool?
    public var minInterval: String?
}

extension ScheduleConfig {
    public func parseInterval() throws -> TimeInterval? {
        guard let interval = self.interval else { return nil }
        return try parseTimeInterval(interval)
    }

    private func determineIntervalScale(_ interval: String) -> TimeInterval? {
        switch interval.last?.lowercased() {
        case "h": return 60.0 * 60.0
        case "m": return 60.0
        case "s": return 1.0
        default: return nil
        }
    }

    public func parseMinInterval() throws -> TimeInterval? {
        guard let minInterval = self.minInterval else { return nil }
        return try parseTimeInterval(minInterval)
    }

    public func parseStartupDelay() throws -> TimeInterval? {
        guard let startupDelay = self.startupDelay else { return nil }
        return try parseTimeInterval(startupDelay)
    }

    private func parseTimeInterval(_ interval: String) throws -> TimeInterval? {
        if let scale = determineIntervalScale(interval) {
            let endIndex = interval.index(interval.endIndex, offsetBy: -2)
            let slicedInterval = interval[...endIndex]
            guard let timeInterval = TimeInterval(slicedInterval) else { return nil }
            return timeInterval * scale
        } else {
            return TimeInterval(interval)
        }
    }
}
