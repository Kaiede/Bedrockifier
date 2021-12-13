//
//  File.swift
//  
//
//  Created by Alex Hadden on 12/13/21.
//

import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
typealias PlatformMode = __darwin_mode_t
#elseif os(Linux)
import Glibc
typealias PlatformMode = __mode_t
#endif

enum PlatformError: Error {
    case Errno(error: Int32)
}

func platformChown(path: String, uid: UInt32?, gid: UInt32?) throws {
    let realUid = uid ?? UInt32.max
    let realGid = gid ?? UInt32.max

    try path.withCString({ cchars in
        let result = chown(cchars, realUid, realGid)
        guard result == 0 else {
            throw PlatformError.Errno(error: errno)
        }
    })
}

func platformChmod(path: String, permissions: UInt16) throws {
    try path.withCString({ cchars in
        let result = chmod(cchars, PlatformMode(permissions))
        guard result == 0 else {
            throw PlatformError.Errno(error: errno)
        }
    })
}
