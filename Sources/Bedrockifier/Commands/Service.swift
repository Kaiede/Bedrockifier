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

import ArgumentParser
import Foundation
import Logging
import PTYKit

extension Bedrockifier {
    struct Service: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "daemon",
            abstract: "Runs the backup service as a daemon in the foreground."
        )

        @Option(help: "Path to the config file")
        var configPath: String?

        @Option(help: "Path to known host keys")
        var hostKeysPath: String?

        @Option(name: .shortAndLong, help: "Path to docker")
        var dockerSocketPath: String?

        @Option(name: .shortAndLong, help: "Folder to read config from")
        var configFolder: String?

        @Option(name: .shortAndLong, help: "Folder to write backups to")
        var backupPath: String?

        @Flag(help: "Log debug level information")
        var debug = false

        @Flag(help: "Log trace level information, overriding --debug")
        var trace = false

        mutating func run() async throws {
            _ = Bedrockifier.initializeTerminal(showDetails: true)
            BackupService.logger.info("Configuring Bedrockifier Daemon")
            let environment = EnvironmentConfig()

            let configUri = Bedrockifier.getConfigFileUrl(
                environment: environment,
                configPath: configPath,
                configFolder: configFolder
            )

            guard FileManager.default.fileExists(atPath: configUri.path) else {
                BackupService.logger.error("Configuration file doesn't exist at path \(configUri.path)")
                return
            }

            guard let config = try? getConfig(from: configUri) else {
                BackupService.logger.error("Unable to read configuration file, fix the above errors and try again")
                return
            }

            let backupPath = self.backupPath ?? config.backupPath ?? environment.dataDirectory
            guard FileManager.default.fileExists(atPath: backupPath) else {
                BackupService.logger.error("Backup folder not found at path \(backupPath)")
                return
            }

            let dockerSocketPath = self.dockerSocketPath ?? config.dockerSocketPath ?? environment.dockerSocketPath
            if !FileManager.default.fileExists(atPath: dockerSocketPath) {
                BackupService.logger.info("Docker socket not found at path \(dockerSocketPath). Using docker to control containers will fail.")
            }

            let hostKeysUri = Bedrockifier.getHostKeyFileUrl(
                environment: environment,
                hostKeysPath: hostKeysPath,
                configFolder: configFolder
            )
            let tools = ToolConfig(
                dockerSocketPath: dockerSocketPath,
                hostKeyValidator: SSHHostKeyValidator(keysFile: hostKeysUri)
            )

            let backupUrl = URL(fileURLWithPath: backupPath)

            updateLoggingLevel(config: config, environment: environment)

            BackupService.logger.info("Configuration Loaded, Running Service...")
            let service = BackupService(
                config: config,
                configDir: URL(fileURLWithPath: environment.configDirectory),
                dataUrl: backupUrl,
                tools: tools
            )

            try await service.run()
        }

        private func getConfig(from configUri: URL) throws -> BackupConfig {
            do {
                BackupService.logger.info("Loading Configuration From: \(configUri.path)")
                return try BackupConfig.getYaml(from: configUri)
            } catch let error {
                BackupService.logger.error("\(error)")
                throw error
            }
        }

        private func updateLoggingLevel(config: BackupConfig, environment: EnvironmentConfig) {
            if trace || config.loggingLevel == .trace {
                ConsoleKitLogger.logLevelOverride = .trace
                ConsoleKitLogger.showFilePosition = true
            } else if debug || config.loggingLevel == .debug {
                ConsoleKitLogger.logLevelOverride = .debug
                ConsoleKitLogger.showFilePosition = true
            }
        }

        private func readBackupConfig(from uri: URL) -> BackupConfig? {
            do {
                return try BackupConfig.getYaml(from: uri)
            } catch let error {
                BackupService.logger.error("\(error.localizedDescription)")
            }

            return nil
        }
    }
}
