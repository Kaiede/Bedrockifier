//
//  File.swift
//  
//
//  Created by Alex Hadden on 12/31/21.
//

import Foundation
import PTYKit
import ZIPFoundation

public class ContainerConnection {
    struct Strings {
        static let dockerConnectError = "Got permission denied while trying to connect to the Docker daemon"
    }

    public struct RconConfig {
        let address: String
        let password: String
    }

    public enum Kind {
        case bedrock
        case java
    }

    private let terminalPath: String
    public let name: String
    let kind: Kind

    public let terminal: PseudoTerminal
    var terminalProcess: Process
    let rconConfig: RconConfig?

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
                terminalPath: String,
                containerName: String,
                rcon: RconConfig?,
                kind: Kind,
                worlds: [String],
                extras: [String]?) throws {
        self.terminalPath = terminalPath
        self.name = containerName
        self.rconConfig = rcon
        self.kind = kind
        self.terminal = terminal
        self.worlds = worlds.map({ URL(fileURLWithPath: $0) })
        self.extras = extras?.map({ URL(fileURLWithPath: $0) })
        self.playerCount = 0
        self.lastBackup = .distantPast

        try self.terminal.setWindowSize(columns: 65000, rows: 24)

        let processUrl = ContainerConnection.getPtyProcess(terminalPath: terminalPath)
        let processArgs = try ContainerConnection.getPtyArguments(containerName: containerName, rconConfig: rconConfig)
        self.terminalProcess = try Process(processUrl, arguments: processArgs, terminal: self.terminal)
    }

    public convenience init(terminalPath: String, containerName: String, rcon: RconConfig?, kind: Kind, worlds: [String], extras: [String]?) throws {
        let terminal = try PseudoTerminal()
        try self.init(terminal: terminal,
                      terminalPath: terminalPath,
                      containerName: containerName,
                      rcon: rcon,
                      kind: kind,
                      worlds: worlds,
                      extras: extras)
    }

    public func start() throws {
        Library.log.debug("Starting Terminal Process. (container: \(name), isRcon: \(rconConfig != nil))")
        try terminalProcess.run()
        logTerminalSize()
    }

    public func stop() async {
        Library.log.debug("Terminating Terminal Process. (container: \(name), isRcon: \(rconConfig != nil))")
        terminalProcess.terminate()
        await terminal.waitForDetach()

        if terminalProcess.isRunning {
            Library.log.error("Terminal Process Still Running. (container: \(name), isRcon: \(rconConfig != nil))")
        }
    }

    public func reset() throws {
        Library.log.debug("Resetting Container Process. (container: \(name), isRcon: \(rconConfig != nil))")
        let processUrl = ContainerConnection.getPtyProcess(terminalPath: terminalPath)
        let processArgs = try ContainerConnection.getPtyArguments(containerName: name, rconConfig: rconConfig)
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

    private static func getPtyArguments(containerName: String, rconConfig: RconConfig?) throws -> [String] {
        if let rconConfig = rconConfig {
            return try getRconArguments(rconConfig: rconConfig)
        } else {
            return getDockerArguments(containerName: containerName)
        }
    }

    private static func getDockerArguments(containerName: String) -> [String] {
        return [
            "attach",
            "--sig-proxy=false",
            containerName
        ]
    }

    private static func getRconArguments(rconConfig: RconConfig) throws -> [String] {
        // TODO: Do some checking here...
        let parts = rconConfig.address.split(whereSeparator: { $0 == ":" })
        guard parts.count == 2 else {
            throw ParseError.invalidHostname(rconConfig.address)
        }

        return [
            "--host",
            "\(parts[0])",
            "--port",
            "\(parts[1])",
            "--password",
            "\(rconConfig.password)"
        ]
    }

    private static func getPtyProcess(terminalPath: String) -> URL {
        return URL(fileURLWithPath: terminalPath)
    }
}

extension ContainerConnection {
    public static func loadContainers(from config: BackupConfig, dockerPath: String, rconPath: String) throws -> [ContainerConnection] {
        var containers: [ContainerConnection] = []
        for container in config.containers?.bedrock ?? [] {
            let processPath = container.rconAddr == nil ? dockerPath : rconPath
            let rconConfig = rconConfig(address: container.rconAddr, password: container.rconPassword)
            let connection = try ContainerConnection(terminalPath: processPath,
                                                     containerName: container.name,
                                                     rcon: rconConfig,
                                                     kind: .bedrock,
                                                     worlds: container.worlds,
                                                     extras: container.extras)
            containers.append(connection)
        }

        for container in config.containers?.java ?? [] {
            let processPath = container.rconAddr == nil ? dockerPath : rconPath
            let rconConfig = rconConfig(address: container.rconAddr, password: container.rconPassword)
            let connection = try ContainerConnection(terminalPath: processPath,
                                                     containerName: container.name,
                                                     rcon: rconConfig,
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
            let connection = try ContainerConnection(terminalPath: dockerPath,
                                                     containerName: containerName,
                                                     rcon: nil,
                                                     kind: .bedrock,
                                                     worlds: worldPaths,
                                                     extras: nil)
            containers.append(connection)
        }

        return containers
    }

    private static func rconConfig(address: String?, password: String?) -> RconConfig? {
        if let address = address, let password = password {
            return RconConfig(address: address, password: password)
        }

        return nil
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
