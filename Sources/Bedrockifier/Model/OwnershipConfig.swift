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

public struct OwnershipConfig: Codable {
    public var chown: String?
    public var permissions: String?
}

extension OwnershipConfig {
    func parseOwnerAndGroup() throws -> (Platform.UserID?, Platform.GroupID?) {
        guard let chownString = self.chown else { return (nil, nil) }
        return try parse(ownership: chownString)
    }

    func parsePosixPermissions() throws -> Platform.Mode? {
        guard let permissionsString = self.permissions else { return nil }
        return try parse(permissions: permissionsString)
    }
}

struct OwnershipPosixConfig {
    fileprivate static let folderDefaultMode: Platform.Mode = 0o777
    fileprivate static let fileDefaultMode: Platform.Mode = 0o666

    var userId: Platform.UserID?
    var groupId: Platform.GroupID?
    var folderMode: Platform.Mode?
    var fileMode: Platform.Mode?

    init(ownership: String?, mask: String?) throws {
        if let ownership {
            let (userId, groupId) = try parse(ownership: ownership)
            self.userId = userId
            self.groupId = groupId
        }

        if let mask {
            let mask = try parse(permissions: mask)
            folderMode = Self.folderDefaultMode & ~mask
            fileMode = Self.fileDefaultMode & ~mask
        }
    }
}

extension OwnershipPosixConfig {
    mutating func fillEmptyOwner(
        from url: URL,
        fillUserId: Bool = true,
        fillGroupId: Bool = true,
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

        if userId == nil, fillUserId, let uid = attributes[.ownerAccountID] as? NSNumber {
            userId = uid.uint32Value
        }

        if groupId == nil, fillGroupId, let gid = attributes[.groupOwnerAccountID] as? NSNumber {
            groupId = gid.uint32Value
        }
    }

    mutating func fillEmptyModes(from url: URL) throws {
        guard folderMode == nil || fileMode == nil else { return }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let modeNumber = attributes[.posixPermissions] as? NSNumber {
            let mode = Platform.Mode(modeNumber.uint16Value)
            var mask = Platform.Mode(0o000)

            mask |= buildMaskOctet(from: mode)
            mask |= buildMaskOctet(from: mode >> 3) << 3

            if folderMode == nil {
                self.folderMode = Self.folderDefaultMode & ~mask
            }
            if fileMode == nil {
                self.fileMode = Self.fileDefaultMode & ~mask
            }
        }
    }
}

fileprivate func buildMaskOctet(from mode: Platform.Mode) -> Platform.Mode {
    if mode & 0o006 == 0 {
        // No read or write, so mask execute too.
        return 0o007
    } else if mode & 0o002 == 0 {
        // No write, so mask write.
        return 0o002
    }

    return 0o000
}
