//
//  File.swift
//  
//
//  Created by Alex Hadden on 11/27/21.
//

import Foundation

enum ParseError: Error {
    case invalidSyntax
    case outOfBounds
}

func parse(ownership: String) throws -> (UInt?, UInt?) {
    // Special Case: ":" Only
    if ownership == ":" {
        return (nil, nil)
    }

    let parts = ownership.split(separator: ":")
    guard parts.count < 3 else {
        throw ParseError.invalidSyntax
    }

    let intParts = parts.map({ UInt($0) })
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

func parse(permissions: String) throws -> Int16 {
    guard let permissionValue = Int16(permissions, radix: 16) else {
        throw ParseError.invalidSyntax
    }

    guard permissionValue <= 0x777 else {
        throw ParseError.outOfBounds
    }

    return permissionValue
}
