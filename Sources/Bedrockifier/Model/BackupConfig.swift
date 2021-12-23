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

    public enum LoggingConfig: String, Codable {
        case debug
        case trace
    }

    public struct ContainerConfig: Codable {
        public var name: String
        public var worlds: [String]
    }

    public struct ServerContainersConfig: Codable {
        public var java: [ContainerConfig]
        public var bedrock: [ContainerConfig]
    }

    public var dockerPath: String?
    public var backupPath: String?
    public var servers: ServerConfig?
    public var containers: ServerContainersConfig?
    public var trim: TrimConfig?
    public var ownership: OwnershipConfig?
    public var schedule: ScheduleConfig?
    public var loggingLevel: LoggingConfig?
}

extension BackupConfig {
    public static func getBackupConfig(from url: URL) throws -> BackupConfig {
        let data = try Data(contentsOf: url)
        return try BackupConfig.getBackupConfig(from: data)
    }

    public static func getBackupConfig(from data: Data) throws -> BackupConfig {
        let decodey = YAMLDecoder()
        let config = try decodey.decode(BackupConfig.self, from: data)
        return config
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

extension BackupConfig.ScheduleConfig {
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
}
