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
    public var interval: String?
    public var daily: DayTime?
    public var onPlayerLogin: Bool?
    public var onPlayerLogout: Bool?
}

extension ScheduleConfig {
    public func parseInterval() throws -> TimeInterval? {
        guard let interval = self.interval else { return nil }

        if let scale = determineIntervalScale(interval) {
            let endIndex = interval.index(interval.endIndex, offsetBy: -2)
            let slicedInterval = interval[...endIndex]
            guard let timeInterval = TimeInterval(slicedInterval) else { return nil }
            return timeInterval * scale
        } else {
            return TimeInterval(interval)
        }
    }

    private func determineIntervalScale(_ interval: String) -> TimeInterval? {
        switch interval.last?.lowercased() {
        case "h": return 60.0 * 60.0
        case "m": return 60.0
        case "s": return 1.0
        default: return nil
        }
    }

    public var usesSingleTerminal: Bool {
        return self.interval != nil || self.daily != nil
    }
}
