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
import PTYKit
import ZIPFoundation

public class ContainerConnection {
    struct Strings {
        static let dockerConnectError = "Got permission denied while trying to connect to the Docker daemon"
    }

    public enum Kind {
        case bedrock
        case java
    }

    public let name: String
    let kind: Kind

    public let terminal: PseudoTerminal
    var terminalProcess: Process
    let connectionConfig: ContainerConnectionConfig

    let worlds: [URL]
    let extras: [URL]?
    var playerCount: Int
    public var lastBackup: Date

    public var isRunning: Bool {
        terminalProcess.isRunning
    }

    private var controlTerminal: PseudoTerminal {
        switch kind {
        case .bedrock: fallthrough
        case .java:
            return terminal
        }
    }

    public init(terminal: PseudoTerminal,
                containerName: String,
                config: ContainerConnectionConfig,
                kind: Kind,
                worlds: [String],
                extras: [String]?) throws {
        self.name = containerName
        self.connectionConfig = config
        self.kind = kind
        self.terminal = terminal
        self.worlds = worlds.map({ URL(fileURLWithPath: $0) })
        self.extras = extras?.map({ URL(fileURLWithPath: $0) })
        self.playerCount = 0
        self.lastBackup = .distantPast

        try self.terminal.setWindowSize(columns: 65000, rows: 24)

        let processUrl = config.processUrl
        let processArgs = try config.makeArguments()
        self.terminalProcess = try Process(processUrl, arguments: processArgs, terminal: self.terminal)
    }

    public convenience init(containerName: String, config: ContainerConnectionConfig, kind: Kind, worlds: [String], extras: [String]?) throws {
        let terminal = try PseudoTerminal(identifier: containerName, newline: config.newline)
        try self.init(terminal: terminal,
                      containerName: containerName,
                      config: config,
                      kind: kind,
                      worlds: worlds,
                      extras: extras)
    }

    public func start() async throws {
        Library.log.debug("Starting Terminal Process. (container: \(name), kind: \(connectionConfig.kind))")
        try terminalProcess.run()
        if connectionConfig.kind == "ssh" {
            try await loginSSH()
        }
        logTerminalSize()
    }

    public func stop() async {
        Library.log.debug("Terminating Terminal Process. (container: \(name), kind: \(connectionConfig.kind))")
        terminalProcess.terminate()
        await terminal.waitForDetach()

        if terminalProcess.isRunning {
            Library.log.error("Terminal Process Still Running. (container: \(name), kind: \(connectionConfig.kind))")
        }
    }

    public func reset() throws {
        Library.log.debug("Resetting Container Process. (container: \(name), kind: \(connectionConfig.kind))")
        let processUrl = connectionConfig.processUrl
        let processArgs = try connectionConfig.makeArguments()
        self.terminalProcess = try Process(processUrl, arguments: processArgs, terminal: terminal)
    }

    public func cleanupIncompleteBackup(destination: URL) async throws {
        guard terminalProcess.isRunning else {
            throw ContainerError.processNotRunning
        }

        guard isSaveHeld(destination: destination) else {
            throw ContainerError.resumeFailed
        }

        try await resumeAutosave()
        try releaseHold(destination: destination)
    }

    public func runBackup(destination: URL) async throws {
        guard terminalProcess.isRunning else {
            throw ContainerError.processNotRunning
        }

        try takeHold(destination: destination)
        do {
            try await pauseAutosave()
        } catch let error {
            // Best effort release the hold if we weren't able to pause saving
            try? releaseHold(destination: destination)
            throw error
        }

        var failedBackups: [String] = []
        Library.log.info("Starting Backup of worlds. (container: \(name))")

        for worldUrl in worlds {
            do {
                let world = try World(url: worldUrl)

                Library.log.info("Backing Up: \(world.name)")
                let backupWorld = try world.backup(to: destination)
                Library.log.info("Backed up as: \(backupWorld.location.lastPathComponent)")
            } catch let error {
                Library.log.error("Backup of world at \(worldUrl.path) failed.")
                Library.log.error("Error: \(error.localizedDescription)")
                Library.log.debug("Error Details: \(error)")
                failedBackups.append(worldUrl.path)
            }
        }

        if let extras = extras {
            Library.log.info("Backing up extras. (container: \(name))")
            do {
                let fileName = try backupExtras(destination: destination, extras: extras)

                Library.log.info("Backed up extras as \(fileName)")
            } catch let error {
                Library.log.error("\(error.localizedDescription)")
                Library.log.error("Backup of \(name) extras failed.")
                failedBackups.append("\(name) extras")
            }
        }

        lastBackup = Date()
        if failedBackups.count > 0 {
            Library.log.error("Backups for \(name) had failures...")
        } else {
            Library.log.info("Backups for \(name) finished successfully...")
        }

        try await resumeAutosave()
        try releaseHold(destination: destination)

        if failedBackups.count > 0 {
            throw ContainerError.backupsFailed(failedBackups)
        }
    }

    public func pauseAutosave() async throws {
        switch kind {
        case .bedrock:
            try await pauseSaveOnBedrock()
        case .java:
            try await pauseSaveOnJava()
        }
    }

    public func resumeAutosave() async throws {
        switch kind {
        case .bedrock:
            try await resumeSaveOnBedrock()
        case .java:
            try await resumeSaveOnJava()
        }
    }

    public func incrementPlayerCount() -> Int {
        playerCount += 1
        return playerCount
    }

    public func decrementPlayerCount() -> Int {
        playerCount = max(0, playerCount - 1)
        return playerCount
    }

    private func backupExtras(destination: URL, extras: [URL]) throws -> String {
        let timestamp = DateFormatter.backupDateFormatter.string(from: Date())
        let fileName = "\(name).extras.\(timestamp).zip"
        let archivePath = destination.appendingPathComponent(fileName)
        Library.log.trace("Extras destination: \(archivePath.path)")

        try FileManager.default.createDirectory(atPath: destination.path,
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        guard let archive = Archive(url: archivePath, accessMode: .create) else {
            throw ContainerError.invalidExtrasArchive
        }

        for extra in extras {
            Library.log.info("Packing \(extra.lastPathComponent)...")
            let dirEnum = FileManager.default.enumerator(atPath: extra.path)
            let folderBase = NSString(string: extra.lastPathComponent)
            while let archiveItem = dirEnum?.nextObject() as? String {
                let archivePath = String(folderBase.appendingPathComponent(archiveItem))
                let fullItemUrl = URL(fileURLWithPath: archiveItem, relativeTo: extra)
                try archive.addEntry(with: archivePath, fileURL: fullItemUrl)
            }
        }

        return fileName
    }

    private func pauseSaveOnBedrock() async throws {
        // Start Save Hold
        try controlTerminal.sendLine("save hold")
        if try await expect(["Saving", "The command is already running"], timeout: 10.0) == .noMatch {
            throw ContainerError.pauseFailed
        }

        // Wait for files to be ready
        var attemptLimit = 3
        while attemptLimit > 0 {
            try controlTerminal.sendLine("save query")
            if try await expect(["Files are now ready to be copied"], timeout: 10.0) == .noMatch {
                attemptLimit -= 1
            } else {
                break
            }
        }

        if attemptLimit < 0 {
            throw ContainerError.saveNotCompleted
        }
    }

    private func pauseSaveOnJava() async throws {
        // Need a longer timeout on the flush in case server is still starting up
        try controlTerminal.sendLine("save-all flush")
        if try await expect(["Saved the game"], timeout: 30.0) == .noMatch {
            throw ContainerError.pauseFailed
        }

        try controlTerminal.sendLine("save-off")
        if try await expect(["Automatic saving is now disabled"], timeout: 10.0) == .noMatch {
            throw ContainerError.pauseFailed
        }
    }

    private func resumeSaveOnBedrock() async throws {
        // Release Save Hold
        try controlTerminal.sendLine("save resume")
        let saveResumeStrings = [
            "Changes to the level are resumed", // 1.17 and earlier
            "Changes to the world are resumed", // 1.18 and later
            "A previous save has not been completed"
        ]
        if try await expect(saveResumeStrings, timeout: 60.0) == .noMatch {
            throw ContainerError.resumeFailed
        }
    }

    private func resumeSaveOnJava() async throws {
        try controlTerminal.sendLine("save-on")
        let saveResumeStrings = [
            "Automatic saving is now enabled",
            "Saving is already turned on"
        ]
        if try await expect(saveResumeStrings, timeout: 60.0) == .noMatch {
            throw ContainerError.resumeFailed
        }
    }

    private func expect(_ expressions: [String], timeout: TimeInterval) async throws -> PseudoTerminal.ExpectResult {
        let possibleErrors = [Strings.dockerConnectError: ContainerError.dockerConnectPermissionError]
        let allExpectations = expressions + possibleErrors.keys

        let result = await terminal.expect(allExpectations, timeout: timeout)
        switch result {
        case .noMatch:
            break
        case .match(let matchString):
            for (errorKey, errorType) in possibleErrors {
                if matchString.contains(errorKey) {
                    throw errorType
                }
            }
        }

        return result
    }

    public func isSaveHeld(destination: URL) -> Bool {
        let holdFile = holdFile(destination: destination)
        return FileManager.default.fileExists(atPath: holdFile.path)
    }

    private func takeHold(destination: URL) throws {
        let holdFile = holdFile(destination: destination)
        if !FileManager.default.fileExists(atPath: holdFile.path) {
            Library.log.debug("Taking save hold on \(name)")
            try Data().write(to: holdFile)
        }
    }

    private func releaseHold(destination: URL) throws {
        let holdFile = holdFile(destination: destination)
        if FileManager.default.fileExists(atPath: holdFile.path) {
            Library.log.debug("Releasing save hold on \(name)")
            try FileManager.default.removeItem(at: holdFile)
        }
    }

    private func holdFile(destination: URL) -> URL {
        destination.appendingPathComponent(".\(self.name).hold")
    }

    private func logTerminalSize() {
        do {
            let windowSize = try terminal.getWindowSize()
            Library.log.debug("Docker Process Window Size Fetched. (cols = \(windowSize.ws_col), rows = \(windowSize.ws_row)")
        } catch {
            Library.log.debug("Failed to get terminal window size")
        }
    }

    private func loginSSH() async throws {
        do {
            let result = await terminal.expect("password:", timeout: 60.0)
            guard result != .noMatch else {
                Library.log.error("Timed out waiting to enter password to minecraft service.")
                return
            }

            Library.log.debug("Sending password: \(connectionConfig.password)")
            try terminal.send("\(connectionConfig.password)\r")

            // Wait before we attempt to issue commands
            try await Task.sleep(for: .seconds(2))
        } catch {
            Library.log.error("Failed to login to minecraft service.")
            throw error
        }
    }
}

extension ContainerConnection {
    public static func loadContainers(from config: BackupConfig, tools: ToolConfig) throws -> [ContainerConnection] {
        var containers: [ContainerConnection] = []
        for container in config.containers?.bedrock ?? [] {
            Library.log.debug("Creating Bedrock Container Connection. (container: \(container.name))")
            let config = containerConfig(container: container, tools: tools)
            let connection = try ContainerConnection(containerName: container.name,
                                                     config: config,
                                                     kind: .bedrock,
                                                     worlds: container.worlds,
                                                     extras: container.extras)
            containers.append(connection)
        }

        for container in config.containers?.java ?? [] {
            Library.log.debug("Creating Java Container Connection. (container: \(container.name)")
            let config = containerConfig(container: container, tools: tools)
            let connection = try ContainerConnection(containerName: container.name,
                                                     config: config,
                                                     kind: .java,
                                                     worlds: container.worlds,
                                                     extras: container.extras)
            containers.append(connection)
        }

        // Offer Backwards Compatibility for Older Installs
        for container in config.servers ?? [:] {
            let containerName = container.key
            let worldsFolder = URL(fileURLWithPath: container.value)
            let worlds = try World.getWorlds(at: worldsFolder)
            let worldPaths = worlds.map({ $0.location.path })
            let config = DockerConnectionConfig(dockerPath: tools.dockerPath, containerName: containerName)
            let connection = try ContainerConnection(containerName: containerName,
                                                     config: config,
                                                     kind: .bedrock,
                                                     worlds: worldPaths,
                                                     extras: nil)
            containers.append(connection)
        }

        return containers
    }

    private static func containerConfig(container: BackupConfig.ContainerConfig, tools: ToolConfig) -> ContainerConnectionConfig {
        if let sshConfig = SSHConnectionConfig(sshpassPath: tools.sshpassPath, sshPath: tools.sshPath, config: container) {
            return sshConfig
        } else if let rconConfig = RCONConnectionConfig(rconPath: tools.rconPath, config: container) {
            return rconConfig
        } else {
            return DockerConnectionConfig(dockerPath: tools.dockerPath, config: container)
        }
    }
}

extension ContainerConnection {
    public enum ContainerError: Error {
        case processNotRunning
        case dockerConnectPermissionError
        case pauseFailed
        case saveNotCompleted
        case resumeFailed
        case backupsFailed([String])
        case invalidExtrasArchive
    }
}

extension ContainerConnection.ContainerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .processNotRunning:
            return "Docker process didn't start successfully, or has died"
        case .dockerConnectPermissionError:
            return "Docker was blocked from accessing docker.sock, make sure UID/GID are set correctly"
        case .pauseFailed:
            return "Server container failed to pause autosave before timeout was reached"
        case .saveNotCompleted:
            return "Server container failed to flush data to disk before timeout was reached"
        case .resumeFailed:
            return "Server container failed to resume autosave before timeout was reached"
        case .backupsFailed(let worlds):
            let worldsString = worlds.joined(separator: ", ")
            return "Server container had worlds that failed to backup: \(worldsString)"
        case .invalidExtrasArchive:
            return "Could not create ZIP archive for extras"
        }
    }
}
