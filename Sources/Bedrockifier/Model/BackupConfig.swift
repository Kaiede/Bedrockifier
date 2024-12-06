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

    public enum LoggingConfig: String, Codable {
        case debug
        case trace
    }

    public struct ContainerConfig: Codable {
        public var name: String
        public var prefixContainerName: Bool?
        public var rcon: String?
        public var ssh: String?
        public var password: String?
        public var passwordFile: String?
        public var extras: [String]?
        public var worlds: [String]
    }

    public struct ServerContainersConfig: Codable {
        public var java: [ContainerConfig]?
        public var bedrock: [ContainerConfig]?
    }

    public var dockerPath: String?
    public var rconPath: String?
    public var sshPath: String?
    public var sshpassPath: String?
    public var backupPath: String?
    public var prefixContainerName: Bool?
    public var servers: ServerConfig?
    public var containers: ServerContainersConfig?
    public var trim: TrimConfig?
    public var ownership: OwnershipConfig?
    public var schedule: ScheduleConfig?
    public var loggingLevel: LoggingConfig?
}

extension BackupConfig.ContainerConfig {
    func containerPassword() -> ContainerPassword {
        if let file = passwordFile {
            return .passwordFile(URL(fileURLWithPath: file))
        } else if let password = password {
            return .password(password)
        }

        return .none
    }
}

internal struct RconCliConfig: Codable {
    public var password: String?
}

extension Decodable {
    public static func getYaml(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        return try Self.getYaml(from: data)
    }

    public static func getYaml(from data: Data) throws -> Self {
        let decoder = YAMLDecoder()
        let config = try decoder.decode(Self.self, from: data)
        return config
    }
}
