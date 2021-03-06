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

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

struct Platform {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    typealias Mode = __darwin_mode_t
    #elseif os(Linux)
    typealias Mode = __mode_t
    #endif

    static func changeOwner(path: String, uid: UInt32?, gid: UInt32?) throws {
        let realUid = uid ?? UInt32.max
        let realGid = gid ?? UInt32.max

        try path.withCString({ cchars in
            let result = chown(cchars, realUid, realGid)
            guard result == 0 else {
                throw PlatformError.errno(error: errno)
            }
        })
    }

    static func changePermissions(path: String, permissions: UInt16) throws {
        try path.withCString({ cchars in
            let result = chmod(cchars, Mode(permissions))
            guard result == 0 else {
                throw PlatformError.errno(error: errno)
            }
        })
    }
}

extension Platform {
    enum PlatformError: Error {
        case errno(error: Int32)
    }
}

extension Platform.PlatformError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .errno(let errorCode): return "Platform returned error code \(errorCode)"
        }
    }
}
