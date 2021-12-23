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

import Bedrockifier

struct Server: ParsableCommand {
    private static let logger = Logger(label: "bedrockifier")

    @Option(help: "Path to the config file")
    var configPath: String?

    @Option(name: .shortAndLong, help: "Path to docker")
    var dockerPath: String?

    @Option(name: .shortAndLong, help: "Folder to write backups to")
    var backupPath: String?

    @Flag(help: "Log debug level information")
    var debug = false

    @Flag(help: "Log trace level information, overriding --debug")
    var trace = false

    mutating func run() throws {
        let environment = EnvironmentConfig()
        var intervalTimer: ServiceTimer<String>?

        Server.logger.info("Initializing Bedrockifier Daemon")

        let configUri = getConfigFileUrl(environment: environment)
        guard FileManager.default.fileExists(atPath: configUri.path) else {
            Server.logger.error("Configuration file doesn't exist at path \(configUri.path)")
            return
        }

        guard let config = try? getConfig(from: configUri) else {
            Server.logger.error("Unable to read configuration file, fix the above errors and try again")
            return
        }

        // TODO: How much of this early checking can be folded into the library?
        let backupPath = self.backupPath ?? config.backupPath ?? environment.dataDirectory
        guard FileManager.default.fileExists(atPath: backupPath) else {
            Server.logger.error("Backup folder not found at path \(backupPath)")
            return
        }

        let dockerPath = self.dockerPath ?? config.dockerPath ?? environment.dockerPath
        guard FileManager.default.fileExists(atPath: dockerPath) else {
            Server.logger.error("Docker not found at path \(dockerPath)")
            return
        }

        let backupUrl = URL(fileURLWithPath: backupPath)
        if !Server.markHealthy(backupUrl: backupUrl) {
            Server.logger.error("Unable to write to backup folder, check that permissions are configured properly")
            return
        }

        updateLoggingLevel(config: config, environment: environment)

        Server.logger.info("Configuration Loaded, Entering Event Loop...")
        do {
            intervalTimer = try startIntervalBackups(config: config,
                                                     environment: environment,
                                                     backupPath: backupPath,
                                                     dockerPath: dockerPath)
        } catch let error {
            Server.logger.error("\(error.localizedDescription)")
            Server.logger.error("Unable to start backup service handlers")
            return
        }

        // Start Event Loop
        dispatchMain()
    }

    private func getConfig(from configUri: URL) throws -> BackupConfig {
        do {
            Server.logger.info("Loading Configuration From: \(configUri.path)")
            return try BackupConfig.getBackupConfig(from: configUri)
        } catch let error {
            Server.logger.error("\(error)")
            throw error
        }
    }

    private func getConfigFileUrl(environment: EnvironmentConfig) -> URL {
        if let configPath = self.configPath {
            return URL(fileURLWithPath: configPath)
        }

        let dataDirectory = URL(fileURLWithPath: environment.dataDirectory)
        let defaultPath = dataDirectory.appendingPathComponent(environment.configFile).path
        if FileManager.default.fileExists(atPath: defaultPath) {
            return URL(fileURLWithPath: defaultPath)
        }

        Server.logger.warning("\(environment.configFile) not found, using older default: \(EnvironmentConfig.fallbackConfigFile)")
        return dataDirectory.appendingPathComponent(EnvironmentConfig.fallbackConfigFile)
    }

    private func updateLoggingLevel(config: BackupConfig, environment: EnvironmentConfig) {
        if trace || config.loggingLevel == .trace {
            ConsoleLogger.logLevelOverride = .trace
            ConsoleLogger.showFilePosition = true
        } else if debug || config.loggingLevel == .debug {
            ConsoleLogger.logLevelOverride = .debug
            ConsoleLogger.showFilePosition = true
        }
    }

    private func startIntervalBackups(config: BackupConfig,
                                      environment: EnvironmentConfig,
                                      backupPath: String,
                                      dockerPath: String) throws -> ServiceTimer<String>? {
        if let interval = try getBackupInterval(config: config, environment: environment) {
            Server.logger.info("Backup Interval: \(interval) seconds")
            let timer = Bedrockifier.ServiceTimer(identifier: "interval", queue: DispatchQueue.main)
            timer.schedule(startingAt: Date(), repeating: .seconds(Int(interval)))
            timer.setHandler {
                Task {
                    await Server.runBackup(config: config,
                                           backupUrl: URL(fileURLWithPath: backupPath),
                                           dockerPath: dockerPath)
                }
            }

            return timer
        }

        return nil
    }

    private func getBackupInterval(config: BackupConfig, environment: EnvironmentConfig) throws -> TimeInterval? {
        if let interval = config.schedule?.interval {
            return try Bedrockifier.parse(interval: interval)
        }

        return try Bedrockifier.parse(interval: environment.backupInterval)
    }

    private static func runBackup(config: BackupConfig, backupUrl: URL, dockerPath: String) async {
        Server.logger.info("Starting Backup")
        do {
            try await WorldBackup.runBackups(config: config, destination: backupUrl, dockerPath: dockerPath)

            if let ownershipConfig = config.ownership {
                Server.logger.info("Performing Ownership Fixup")
                try WorldBackup.fixOwnership(at: backupUrl, config: ownershipConfig)
            }

            if let trimJob = config.trim {
                Server.logger.info("Performing Trim Jobs")
                try WorldBackup.trimBackups(at: backupUrl,
                                            dryRun: false,
                                            trimDays: trimJob.trimDays,
                                            keepDays: trimJob.keepDays,
                                            minKeep: trimJob.minKeep)
            }

            Server.logger.info("Backup Completed")
            _ = Server.markHealthy(backupUrl: backupUrl)
        } catch let error {
            Server.logger.error("\(error.localizedDescription)")
            Server.logger.error("Backup Failed")
            _ = Server.markUnhealthy(backupUrl: backupUrl)
        }
    }

    static private func markHealthy(backupUrl: URL) -> Bool {
        do {
            let healthFile = healthyFilePath(backupUrl: backupUrl)
            if !FileManager.default.fileExists(atPath: healthFile.path) {
                try Data().write(to: healthFile)
            }
            return true
        } catch let error {
            Server.logger.error("\(error.localizedDescription)")
            Server.logger.error("Unable to mark service as healthy.")
        }

        return false
    }

    static private func markUnhealthy(backupUrl: URL) -> Bool {
        do {
            let healthFile = healthyFilePath(backupUrl: backupUrl)
            if FileManager.default.fileExists(atPath: healthFile.path) {
                try FileManager.default.removeItem(at: healthFile)
            }
            return true
        } catch let error {
            Server.logger.error("\(error.localizedDescription)")
            Server.logger.error("Unable to mark service as unhealthy.")
        }

        return false
    }

    static private func healthyFilePath(backupUrl: URL) -> URL {
        return backupUrl.appendingPathComponent(".service_is_healthy")
    }

    private func readBackupConfig(from uri: URL) -> BackupConfig? {
        do {
            return try BackupConfig.getBackupConfig(from: uri)
        } catch let error {
            Server.logger.error("\(error.localizedDescription)")
        }

        return nil
    }
}

// Initialize Service
ConsoleLogger.showDetails = true
LoggingSystem.bootstrap(ConsoleLogger.init)
Server.main()
