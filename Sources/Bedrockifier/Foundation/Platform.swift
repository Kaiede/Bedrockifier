//
//  File.swift
//  
//
//  Created by Alex Hadden on 12/13/21.
//

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

    enum PlatformError: Error {
        case Errno(error: Int32)
    }

    static func changeOwner(path: String, uid: UInt32?, gid: UInt32?) throws {
        let realUid = uid ?? UInt32.max
        let realGid = gid ?? UInt32.max

        try path.withCString({ cchars in
            let result = Darwin.chown(cchars, realUid, realGid)
            guard result == 0 else {
                throw PlatformError.Errno(error: errno)
            }
        })
    }

    static func changePermissions(path: String, permissions: UInt16) throws {
        try path.withCString({ cchars in
            let result = chmod(cchars, Mode(permissions))
            guard result == 0 else {
                throw PlatformError.Errno(error: errno)
            }
        })
    }
}


