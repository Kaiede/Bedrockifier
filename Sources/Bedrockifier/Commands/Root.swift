/*
 Bedrockifier

 Copyright (c) 2026 Adam Thayer
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

import ArgumentParser
import ConsoleKitTerminal
import Logging

@main
struct Bedrockifier: AsyncParsableCommand {
    fileprivate static let logger = Logger(label: "bedrockifier")

    static let configuration = CommandConfiguration(
        abstract: "A utility for backing up Minecraft servers.",
        subcommands: [ClearHostKeys.self, Pack.self, Restore.self, Service.self, Token.self, Trim.self, Unpack.self],
    )

    internal static func initializeTerminal(showDetails: Bool = false) -> Terminal {
        let terminal = Terminal()
        ConsoleKitLogger.showDetails = showDetails
        LoggingSystem.bootstrap({ label in ConsoleKitLogger(label: label, terminal: terminal) })

        return terminal
    }

    internal static func getConfigFileUrl(environment: EnvironmentConfig, configPath: String?, configFolder: String?) -> URL {
        if let configPath {
            return URL(fileURLWithPath: configPath)
        }

        let configDirectory = URL(fileURLWithPath: configFolder ?? environment.configDirectory)
        let defaultPath = configDirectory.appendingPathComponent(environment.configFile).path
        if FileManager.default.fileExists(atPath: defaultPath) {
            return URL(fileURLWithPath: defaultPath)
        }

        Self.logger.notice(
            "\(environment.configFile) not found, using older default: \(EnvironmentConfig.fallbackConfigFile)"
        )
        return configDirectory.appendingPathComponent(EnvironmentConfig.fallbackConfigFile)
    }

    internal static func getHostKeyFileUrl(environment: EnvironmentConfig, hostKeysPath: String?, configFolder: String?) -> URL {
        if let hostKeysPath {
            return URL(fileURLWithPath: hostKeysPath)
        }

        let configDirectory = URL(fileURLWithPath: configFolder ?? environment.configDirectory)
        return configDirectory.appendingPathComponent(environment.hostKeysFile)
    }
}
