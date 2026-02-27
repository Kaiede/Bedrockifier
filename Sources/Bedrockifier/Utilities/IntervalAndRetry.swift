/*
 Bedrockifier

 Copyright (c) 2021-2022 Adam Thayer & Austin St. Aubin
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

package enum ListenerReconnectIntervalConfig {
    package static let minimumInterval: TimeInterval = 5.0
    package static let defaultInterval: TimeInterval = 60.0

    package static func parse(_ interval: String?) throws -> TimeInterval? {
        guard let interval else {
            return nil
        }

        let parsedInterval = try Bedrockifier.parse(interval: interval)
        return max(minimumInterval, parsedInterval)
    }
}

package func retrySaveQuery(
    maxAttempts: Int = 3,
    _ attempt: () async throws -> Bool
) async throws -> Bool {
    var attemptsRemaining = max(0, maxAttempts)

    while attemptsRemaining > 0 {
        if try await attempt() {
            return true
        }

        attemptsRemaining -= 1
    }

    return false
}
