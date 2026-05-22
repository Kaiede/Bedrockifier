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

extension Bedrockifier {
    struct Token: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "token",
            abstract: "Prints the HTTP token to access the running service."
        )

        @Option(help: "Path to the config file")
        var configPath: String?

        @Option(name: .shortAndLong, help: "Folder to read config from")
        var configFolder: String?

        func run() async throws {
            let terminal = initializeTerminal()
            let environment = EnvironmentConfig()
            let configUri = Bedrockifier.getConfigFileUrl(
                environment: environment,
                configPath: configPath,
                configFolder: configFolder
            )
            let configDir = URL(fileURLWithPath: configFolder ?? environment.configDirectory)

            let tokenUrl: URL
            if FileManager.default.fileExists(atPath: configUri.path),
               let config = try? BackupConfig.getYaml(from: configUri) {
                tokenUrl = config.tokenFileUrl(configDir: configDir)
            } else {
                tokenUrl = BackupConfig.defaultTokenFileUrl(configDir: configDir)
            }

            guard let token = try? String(contentsOf: tokenUrl, encoding: .utf8) else {
                terminal.error("Could not read token at \(tokenUrl.path). Is the service running?")
                return
            }

            terminal.output("HTTP Token: ".consoleText(.info) + token.trimmingCharacters(in: .whitespacesAndNewlines).consoleText())
        }
    }
}
