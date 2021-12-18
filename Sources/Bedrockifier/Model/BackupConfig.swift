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
import Yams

public struct BackupConfig: Codable {
    public typealias ServerConfig = [String: String]

    public struct TrimConfig: Codable {
        public var trimDays: Int?
        public var keepDays: Int?
        public var minKeep: Int?
    }

    public struct OwnershipConfig: Codable {
        public var chown: String?
        public var permissions: String?
    }

    public struct ScheduleConfig: Codable {
        public var interval: String?
        public var onPlayerLogin: Bool?
        public var onPlayerLogout: Bool?
    }

    public var dockerPath: String?
    public var backupPath: String?
    public var servers: ServerConfig
    public var trim: TrimConfig?
    public var ownership: OwnershipConfig?
    public var schedule: ScheduleConfig?
}

extension BackupConfig {
    public static func getBackupConfig(from url: URL) throws -> BackupConfig {
        let data = try Data(contentsOf: url)
        return try BackupConfig.getBackupConfig(from: data)
    }

    public static func getBackupConfig(from data: Data) throws -> BackupConfig {
        let decodey = YAMLDecoder()
        let config = try decodey.decode(BackupConfig.self, from: data)
        try config.validate(requireSchedule: false)
        return config
    }
}

extension BackupConfig {
    func validate(requireSchedule: Bool) throws {
        if requireSchedule {
            guard let schedule = self.schedule else {
                return // TODO: Throw Missing Schedule
            }

            if schedule.interval == nil && schedule.onPlayerLogin != true && schedule.onPlayerLogout != true {
                return // TODO: Throw needs at at least one schedule type
            }

            // TODO: Validate interval
        }
    }
}

extension BackupConfig.OwnershipConfig {
    func parseOwnerAndGroup() throws -> (UInt32?, UInt32?) {
        guard let chownString = self.chown else { return (nil, nil) }
        return try parse(ownership: chownString)
    }

    func parsePosixPermissions() throws -> UInt16? {
        guard let permissionsString = self.permissions else { return nil }
        return try parse(permissions: permissionsString)
    }
}
