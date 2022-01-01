//
//  File.swift
//  
//
//  Created by Alex Hadden on 12/31/21.
//

import Foundation
import PTYKit

private let usePty = false

public class ContainerConnection {
    public enum ContainerError: Error {
        case processNotRunning
        case pauseFailed
        case saveNotCompleted
        case resumeFailed
    }

    public enum Kind {
        case bedrock
        case java
    }

    private let dockerPath: String
    public let name: String
    let kind: Kind
    public let terminal: PseudoTerminal
    var dockerProcess: Process
    let worlds: [URL]
    var playerCount: Int
    public var lastBackup: Date

    public init(terminal: PseudoTerminal, dockerPath: String, containerName: String, kind: Kind, worlds: [String]) throws {
        self.dockerPath = dockerPath
        self.name = containerName
        self.kind = kind
        self.terminal = terminal
        self.worlds = worlds.map({ URL(fileURLWithPath: $0) })
        self.playerCount = 0
        self.lastBackup = .distantPast

        let processUrl = ContainerConnection.getPtyProcess(dockerPath: dockerPath)
        let processArgs = ContainerConnection.getPtyArguments(dockerPath: dockerPath, containerName: containerName)
        self.dockerProcess = try Process(processUrl, arguments: processArgs, terminal: self.terminal)
    }

    public convenience init(dockerPath: String, containerName: String, kind: Kind, worlds: [String]) throws {
        let terminal = try PseudoTerminal()
        try self.init(terminal: terminal, dockerPath: dockerPath, containerName: containerName, kind: kind, worlds: worlds)
    }

    public func start() throws {
        Library.log.debug("Starting Container Process")
        try dockerProcess.run()
    }

    public func stop() async {
        if usePty {
            Library.log.debug("Detaching Docker Process")
            try? terminal.send("Q")
            await terminal.waitForDetach()
        } else {
            Library.log.debug("Terminating Docker Process")
            dockerProcess.terminate()
            await terminal.waitForDetach()
        }

        if dockerProcess.isRunning {
            Library.log.error("Docker Process Still Running")
        }
    }

    public func reset() throws {
        Library.log.debug("Reseting Container Process")
        let processUrl = ContainerConnection.getPtyProcess(dockerPath: dockerPath)
        let processArgs = ContainerConnection.getPtyArguments(dockerPath: dockerPath, containerName: name)
        self.dockerProcess = try Process(processUrl, arguments: processArgs, terminal: terminal)
    }

    public func runBackup(destination: URL) async throws {
        guard dockerProcess.isRunning else {
            throw ContainerError.processNotRunning
        }

        try await pauseAutosave()

        do {
            Library.log.info("Starting Backup of worlds for: \(name))")

            for worldUrl in worlds {
                let world = try World(url: worldUrl)

                Library.log.info("Backing Up: \(world.name)")
                let backupWorld = try world.backup(to: destination)
                Library.log.info("Backed up as: \(backupWorld.location.lastPathComponent)")
            }

            lastBackup = Date()
            Library.log.info("Backups for \(name) Complete...")
        } catch let error {
            Library.log.error("\(error.localizedDescription)")
            Library.log.error("Backups for \(name) failed.")
        }

        try await resumeAutosave()
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

    private func pauseSaveOnBedrock() async throws {
        // Start Save Hold
        try terminal.sendLine("save hold")
        if await terminal.expect(["Saving", "The command is already running"], timeout: 10.0) == .noMatch {
            throw ContainerError.pauseFailed
        }

        // Wait for files to be ready
        var attemptLimit = 3
        while attemptLimit > 0 {
            try terminal.sendLine("save query")
            if await terminal.expect("Files are now ready to be copied", timeout: 10.0) == .noMatch {
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
        try terminal.sendLine("save-all flush")
        if await terminal.expect(["Saved the game"], timeout: 30.0) == .noMatch {
            throw ContainerError.pauseFailed
        }

        try terminal.sendLine("save-off")
        if await terminal.expect(["Automatic saving is now disabled"], timeout: 10.0) == .noMatch {
            throw ContainerError.pauseFailed
        }
    }

    private func resumeSaveOnBedrock() async throws {
        // Release Save Hold
        try terminal.sendLine("save resume")
        let saveResumeStrings = [
            "Changes to the level are resumed", // 1.17 and earlier
            "Changes to the world are resumed", // 1.18 and later
            "A previous save has not been completed"
        ]
        if await terminal.expect(saveResumeStrings, timeout: 60.0) == .noMatch {
            throw ContainerError.resumeFailed
        }
    }

    private func resumeSaveOnJava() async throws {
        try terminal.sendLine("save-on")
        if await terminal.expect(["Automatic saving is now enabled"], timeout: 60.0) == .noMatch {
            throw ContainerError.resumeFailed
        }
    }

    private static func getPtyArguments(dockerPath: String, containerName: String) -> [String] {
        if usePty {
            // Use the detach functionality when a tty is configured
            return [
                "-c",
                "\(dockerPath) attach --detach-keys=Q \(containerName)"
            ]
        } else {
            // Without a tty, use a termination signal instead
            return [
                "attach",
                "--sig-proxy=false",
                containerName
            ]
        }
    }

    private static func getPtyProcess(dockerPath: String) -> URL {
        if usePty {
            // Use a shell for the tty capability
            return URL(fileURLWithPath: "/bin/sh")
        } else {
            return URL(fileURLWithPath: dockerPath)
        }
    }
}

extension ContainerConnection {
    public static func loadContainers(from config: BackupConfig, dockerPath: String) throws -> [ContainerConnection] {
        var containers: [ContainerConnection] = []
        for container in config.containers?.bedrock ?? [] {
            let connection = try ContainerConnection(dockerPath: dockerPath, containerName: container.name, kind: .bedrock, worlds: container.worlds)
            containers.append(connection)
        }

        for container in config.containers?.java ?? [] {
            let connection = try ContainerConnection(dockerPath: dockerPath, containerName: container.name, kind: .java, worlds: container.worlds)
            containers.append(connection)
        }

        // Offer Backwards Compatibility for Older Installs
        for container in config.servers ?? [:] {
            let containerName = container.key
            let worldsFolder = URL(fileURLWithPath: container.value)
            let worlds = try World.getWorlds(at: worldsFolder)
            let worldPaths = worlds.map({ $0.location.path })
            let connection = try ContainerConnection(dockerPath: dockerPath, containerName: containerName, kind: .bedrock, worlds: worldPaths)
            containers.append(connection)
        }

        return containers
    }
}
