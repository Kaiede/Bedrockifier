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

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#endif

struct Platform {
    #if canImport(Darwin)
    typealias Mode = __darwin_mode_t
    typealias UserID = __darwin_uid_t
    typealias GroupID = __darwin_gid_t
    #elseif canImport(Glibc) || canImport(Musl)
    typealias Mode = __mode_t
    typealias UserID = __uid_t
    typealias GroupID = __gid_t
    #endif

    static func currentUmask() -> Mode {
        let currentUmask = umask(0)
        umask(currentUmask)
        return currentUmask
    }

    static func changeOwner(path: String, uid: UserID?, gid: GroupID?) throws {
        let realUid = uid ?? UInt32.max
        let realGid = gid ?? UInt32.max

        try path.withCString({ cchars in
            let result = chown(cchars, realUid, realGid)
            guard result == 0 else {
                throw PlatformError.errno(error: errno)
            }
        })
    }

    static func changePermissions(path: String, permissions: Mode) throws {
        try path.withCString({ cchars in
            let result = chmod(cchars, permissions)
            guard result == 0 else {
                throw PlatformError.errno(error: errno)
            }
        })
    }

    static func timingsafeCompare(_ lhs: String, _ rhs: String) -> Bool {
        return timingsafeCompare(Array(lhs.utf8), Array(rhs.utf8))
    }

    static func timingsafeCompare(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == brhscount else { return false }
        return lhs.withUnsafeBytes { lhsPtr in
            rhs.withUnsafeBytes { rhsPtr in
                #if canImport(Darwin) || canImport(Musl)
                return timingsafe_bcmp(lhsPtr.baseAddress, rhsPtr.baseAddress, lhs.count) == 0
                #else
                // glibc < 2.37 does not provide timingsafe_bcmp
                var result: UInt8 = 0
                let lhsBind = lhsPtr.bindMemory(to: UInt8.self)
                let rhsBind = rhsPtr.bindMemory(to: UInt8.self)
                for index in 0..<lhs.count { result |= lhsBind[index] ^ rhsBind[index] }
                return result == 0
                #endif
            }
        }
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
