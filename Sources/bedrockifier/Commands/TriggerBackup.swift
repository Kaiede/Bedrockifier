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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import ArgumentParser
import ConsoleKitTerminal

import BedrockifierLib

extension Bedrockifier {
    struct TriggerBackup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "trigger-backup",
            abstract: "Triggers an immediate backup via the running service."
        )

        @Option(help: "Path to the config file")
        var configPath: String?

        @Option(name: .shortAndLong, help: "Folder to read config from")
        var configFolder: String?

        @Option(help: "Path to the token file (overrides config-derived path)")
        var tokenPath: String?

        @Option(help: "Host to call (default = 127.0.0.1)")
        var host: String = "127.0.0.1"

        @Option(help: "Port to call (default = 8080)")
        var port: Int = 8080

        @Option(help: "Path to call (default = /start-backup)")
        var path: String = "/start-backup"

        @Option(help: "Request timeout in seconds (default = 30)")
        var timeout: Double = 30

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
            if let tokenPath {
                tokenUrl = URL(fileURLWithPath: tokenPath)
            } else if FileManager.default.fileExists(atPath: configUri.path),
                      let config = try? BackupConfig.getYaml(from: configUri) {
                tokenUrl = config.tokenFileUrl(configDir: configDir)
            } else {
                tokenUrl = BackupConfig.defaultTokenFileUrl(configDir: configDir)
            }

            guard let token = try? String(contentsOf: tokenUrl, encoding: .utf8) else {
                terminal.error("Could not read token at \(tokenUrl.path). Is the service running?")
                throw ExitCode.failure
            }

            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedToken.isEmpty else {
                terminal.error("Token file is empty: \(tokenUrl.path)")
                throw ExitCode.failure
            }

            let (url, request) = try makeRequest(terminal: terminal, token: trimmedToken)
            let response: URLResponse
            do {
                (_, response) = try await URLSession.shared.data(for: request)
            } catch {
                terminal.error(
                    "Backup trigger failed reaching \(url.absoluteString): \(error.localizedDescription). " +
                    "If this keeps happening, restart the backup service container."
                )
                throw ExitCode.failure
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                terminal.error("Backup trigger received non-HTTP response from \(url.absoluteString).")
                throw ExitCode.failure
            }

            let status = httpResponse.statusCode
            if (200..<300).contains(status) {
                terminal.output("Backup triggered successfully (HTTP \(status)).".consoleText(.info))
                return
            }

            terminal.error("Backup trigger failed (HTTP \(status)).")
            throw ExitCode.failure
        }

        private func makeRequest(terminal: Terminal, token: String) throws -> (URL, URLRequest) {
            var components = URLComponents()
            components.scheme = "http"
            components.host = host
            components.port = port
            components.path = path.hasPrefix("/") ? path : "/\(path)"

            guard let url = components.url else {
                terminal.error("Invalid backup trigger URL.")
                throw ExitCode.failure
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            return (url, request)
        }
    }
}
