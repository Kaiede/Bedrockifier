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

// Get configuration settings from environment for things that are supported
struct EnvironmentConfig {
    static let fallbackConfigFile = "config.json"

    static let dataDirVariable = "DATA_DIR"

    static let defaultConfigPath = "/config"
    static let defaultDataPath = "/data"
    static let defaultOldDataPath = "/backups"


    // External Tools in Container
    let dockerPath: String
    let rconPath: String

    // Config Folder Settings
    let configDirectory: String
    let configFile: String
    let hostKeysFile: String

    // Data Folder Settings
    let dataDirectory: String

    // Deprecated Settings
    let backupInterval: String?

    init() {
        // External Tools in Container
        self.dockerPath = ProcessInfo.processInfo.environment["DOCKER_PATH"] ?? "/usr/bin/docker"
        self.rconPath = ProcessInfo.processInfo.environment["RCON_PATH"] ?? "/usr/local/bin/rcon-cli"

        // Config Folder Settings
        self.configDirectory = EnvironmentConfig.configDirectory()
        self.configFile = ProcessInfo.processInfo.environment["CONFIG_FILE"] ?? "config.yml"
        self.hostKeysFile = ProcessInfo.processInfo.environment["HOST_KEYS_FILE"] ?? ".authorizedKeys"

        // Data Folder Settings
        self.dataDirectory = EnvironmentConfig.dataDirectory()

        // Deprecated Settings
        self.backupInterval = ProcessInfo.processInfo.environment["BACKUP_INTERVAL"]
    }

    private static func configDirectory() -> String {
        if let envPath = ProcessInfo.processInfo.environment["CONFIG_DIR"] {
            return envPath
        }

        if FileManager.default.fileExists(atPath: defaultConfigPath) {
            return defaultConfigPath
        }

        if let dataEnvPath = ProcessInfo.processInfo.environment[dataDirVariable] {
            return dataEnvPath
        }

        if FileManager.default.fileExists(atPath: defaultDataPath) {
            return defaultDataPath
        }

        return defaultOldDataPath
    }

    private static func dataDirectory() -> String {
        if let dataEnvPath = ProcessInfo.processInfo.environment[dataDirVariable] {
            return dataEnvPath
        }

        if FileManager.default.fileExists(atPath: defaultDataPath) {
            return defaultDataPath
        }

        return defaultOldDataPath
    }
}
