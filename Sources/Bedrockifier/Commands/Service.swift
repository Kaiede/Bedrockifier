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
    struct Service: ParsableCommand {
        fileprivate static let logger = Logger(label: "bedrockifier")
        
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
        
        mutating func run() {
            ConsoleLogger.showDetails = true
            LoggingSystem.bootstrap(ConsoleLogger.init)
            
            Self.logger.info("Configuring Bedrockifier Daemon")
            let environment = EnvironmentConfig()
            
            let configUri = getConfigFileUrl(environment: environment)
            guard FileManager.default.fileExists(atPath: configUri.path) else {
                Self.logger.error("Configuration file doesn't exist at path \(configUri.path)")
                return
            }
            
            guard let config = try? getConfig(from: configUri) else {
                Self.logger.error("Unable to read configuration file, fix the above errors and try again")
                return
            }
            
            let backupPath = self.backupPath ?? config.backupPath ?? environment.dataDirectory
            guard FileManager.default.fileExists(atPath: backupPath) else {
                Self.logger.error("Backup folder not found at path \(backupPath)")
                return
            }
            
            let dockerSocketPath = self.dockerSocketPath ?? config.dockerSocketPath ?? environment.dockerSocketPath
            if !FileManager.default.fileExists(atPath: dockerSocketPath) {
                Self.logger.info("Docker socket not found at path \(dockerSocketPath). Using docker to control containers will fail.")
            }
            
            let hostKeysUri = getHostKeyFileUrl(environment: environment)
            let tools = ToolConfig(
                dockerSocketPath: dockerSocketPath,
                hostKeyValidator: SSHHostKeyValidator(keysFile: hostKeysUri)
            )
            
            let backupUrl = URL(fileURLWithPath: backupPath)
            
            updateLoggingLevel(config: config, environment: environment)
            
            Self.logger.info("Configuration Loaded, Running Service...")
            do {
                let service = BackupService(
                    config: config,
                    configDir: URL(fileURLWithPath: environment.configDirectory),
                    dataUrl: backupUrl,
                    tools: tools
                )
                
                try service.run()
            } catch let error {
                Self.logger.error("Starting Service Failed")
                Self.logger.error("\(error.localizedDescription)")
            }
        }
        
        private func getConfig(from configUri: URL) throws -> BackupConfig {
            do {
                Self.logger.info("Loading Configuration From: \(configUri.path)")
                return try BackupConfig.getYaml(from: configUri)
            } catch let error {
                Self.logger.error("\(error)")
                throw error
            }
        }
        
        private func getConfigFileUrl(environment: EnvironmentConfig) -> URL {
            if let configPath = self.configPath {
                return URL(fileURLWithPath: configPath)
            }
            
            let configDirectory = URL(fileURLWithPath: self.configFolder ?? environment.configDirectory)
            let defaultPath = configDirectory.appendingPathComponent(environment.configFile).path
            if FileManager.default.fileExists(atPath: defaultPath) {
                return URL(fileURLWithPath: defaultPath)
            }
            
            Self.logger.warning(
                "\(environment.configFile) not found, using older default: \(EnvironmentConfig.fallbackConfigFile)"
            )
            return configDirectory.appendingPathComponent(EnvironmentConfig.fallbackConfigFile)
        }
        
        private func getHostKeyFileUrl(environment: EnvironmentConfig) -> URL {
            if let hostKeysPath = self.hostKeysPath {
                return URL(fileURLWithPath: hostKeysPath)
            }
            
            let configDirectory = URL(fileURLWithPath: environment.configDirectory)
            let defaultPath = configDirectory.appendingPathComponent(environment.hostKeysFile).path
            return URL(fileURLWithPath: defaultPath)
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
        
        private func readBackupConfig(from uri: URL) -> BackupConfig? {
            do {
                return try BackupConfig.getYaml(from: uri)
            } catch let error {
                Self.logger.error("\(error.localizedDescription)")
            }
            
            return nil
        }
    }
}
