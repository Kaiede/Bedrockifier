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

extension String {
    public func contains(oneOf others: [String]) -> Bool {
        for other in others {
            if self.contains(other) {
                return true
            }
        }

        return false
    }
}

enum ParseError: Error {
    case invalidSyntax
    case outOfBounds
}

func parse(ownership: String) throws -> (UInt32?, UInt32?) {
    // Special Case: ":" Only
    if ownership == ":" {
        return (nil, nil)
    }

    let parts = ownership.split(separator: ":")
    guard parts.count < 3 else {
        throw ParseError.invalidSyntax
    }

    let intParts = parts.map({ UInt32($0) })
    guard !intParts.contains(nil) else {
        throw ParseError.invalidSyntax
    }

    let finalParts = intParts.compactMap({ $0 })

    // Special Case: Group Only
    if finalParts.count == 1 && ownership.starts(with: ":") {
        return (nil, finalParts[0])
    }

    // Special Case: Onwer Only
    if finalParts.count == 1 {
        return (finalParts[0], nil)
    }

    return (finalParts[0], finalParts[1])
}

func parse(permissions: String) throws -> UInt16 {
    guard let permissionValue = UInt16(permissions, radix: 8) else {
        throw ParseError.invalidSyntax
    }

    guard permissionValue <= 0o777 else {
        throw ParseError.outOfBounds
    }

    return permissionValue
}

public func parse(interval: String) throws -> TimeInterval {
    if let scale = determineIntervalScale(interval) {
        let endIndex = interval.index(interval.endIndex, offsetBy: -2)
        let slicedInterval = interval[...endIndex]
        guard let timeInterval = TimeInterval(slicedInterval) else {
            throw ParseError.invalidSyntax
        }
        return timeInterval * scale
    } else {
        guard let timeInterval = TimeInterval(interval) else {
            throw ParseError.invalidSyntax
        }
        return timeInterval
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
