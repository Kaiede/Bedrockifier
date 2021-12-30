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
import Logging
import PTYKit

private let usePty = false
private let logger = Logger(label: "BedrockifierCLI:WorldBackup")

public class WorldBackup {
    enum Action {
        case keep
        case trim
    }

    var action: Action = .keep
    let modificationDate: Date
    let world: World

    init(world: World, date: Date) {
        self.modificationDate = date
        self.world = world
    }
}

public enum WorldBackupError: Error {
    case holdFailed
    case queryFailed
    case resumeFailed
}

extension WorldBackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .holdFailed:
            return "Failed to pause auto-save on the server"
        case .queryFailed:
            return "Failed to confirm data is ready for backup"
        case .resumeFailed:
            return "Failed to resume auto-save on the server"
        }
    }
}

extension WorldBackup {
    static func getPtyArguments(dockerPath: String, containerName: String) -> [String] {
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

    static func getPtyProcess(dockerPath: String) -> URL {
        if usePty {
            // Use a shell for the tty capability
            return URL(fileURLWithPath: "/bin/sh")
        } else {
            return URL(fileURLWithPath: dockerPath)
        }
    }

    static func stopProcess(_ process: PTYProcess) async {
        if usePty {
            logger.debug("Detaching Docker Process")
            try? process.send("Q")
            await process.waitUntilExit()
        } else {
            logger.debug("Terminating Docker Process")
            await process.terminate()
        }

        if process.isRunning {
            logger.error("Docker Process Still Running")
        }
    }

    public static func runBackups(config: BackupConfig, destination: URL, dockerPath: String) async throws {
        // Original Backup Logic
        if let servers = config.servers {
            for (serverContainer, serverWorldsPath) in servers {
                let worldsUrl = URL(fileURLWithPath: serverWorldsPath)
                try await WorldBackup.makeBackup(backupUrl: destination,
                                           dockerPath: dockerPath,
                                           containerName: serverContainer,
                                           worldsPath: worldsUrl)
            }
        }

        // Modern Backup Logic
        if let bedrockContainers = config.containers?.bedrock {
            try await runBackupsForContainers(bedrockContainers,
                                              destination: destination,
                                              dockerPath: dockerPath,
                                              bedrock: true)
        }

        if let javaContainers = config.containers?.java {
            try await runBackupsForContainers(javaContainers,
                                              destination: destination,
                                              dockerPath: dockerPath,
                                              bedrock: false)
        }
    }

    private static func runBackupsForContainers(_ containers: [BackupConfig.ContainerConfig], destination: URL, dockerPath: String, bedrock: Bool) async throws {
        for container in containers {
            let process = try await pauseSaveOnServer(dockerPath: dockerPath, container: container.name, bedrock: bedrock)

            do {
                Library.log.info("Starting Backup of worlds for: \(container.name))")
                for worldUrl in container.worlds.map({ URL(fileURLWithPath: $0) }) {
                    let world = try World(url: worldUrl)

                    Library.log.info("Backing Up: \(world.name)")
                    let backupWorld = try world.backup(to: destination)
                    Library.log.info("Backed up as: \(backupWorld.location.lastPathComponent)")
                }

                Library.log.info("Backups for \(container.name) Complete...")
            } catch let error {
                Library.log.error("\(error.localizedDescription)")
                Library.log.error("Backups for \(container.name) failed.")
            }

            try await resumeSaveOnServer(process: process, bedrock: bedrock)
        }
    }

    private static func pauseSaveOnServer(dockerPath: String, container: String, bedrock: Bool) async throws -> PTYProcess {
        let arguments: [String] = getPtyArguments(dockerPath: dockerPath, containerName: container)

        // Attach To Container
        let process = try PTYProcess(getPtyProcess(dockerPath: dockerPath), arguments: arguments)
        try process.run()

        do {
            if bedrock {
                try await pauseSaveOnBedrock(process: process)
            } else {
                try await pauseSaveOnJava(process: process)
            }

            return process
        } catch let error {
            await stopProcess(process)
            throw error
        }
    }

    private static func pauseSaveOnBedrock(process: PTYProcess) async throws {
        // Start Save Hold
        try process.sendLine("save hold")
        if await process.expect(["Saving", "The command is already running"], timeout: 10.0) == .noMatch {
            throw WorldBackupError.holdFailed
        }

        // Wait for files to be ready
        var attemptLimit = 3
        while attemptLimit > 0 {
            try process.sendLine("save query")
            if await process.expect("Files are now ready to be copied", timeout: 10.0) == .noMatch {
                attemptLimit -= 1
            } else {
                break
            }
        }

        if attemptLimit < 0 {
            throw WorldBackupError.queryFailed
        }
    }

    private static func pauseSaveOnJava(process: PTYProcess) async throws {
        // Need a longer timeout on the flush in case server is still starting up
        try process.sendLine("save-all flush")
        if await process.expect(["Saved the game"], timeout: 30.0) == .noMatch {
            throw WorldBackupError.holdFailed
        }

        try process.sendLine("save-off")
        if await process.expect(["Automatic saving is now disabled"], timeout: 10.0) == .noMatch {
            throw WorldBackupError.holdFailed
        }
    }

    private static func resumeSaveOnServer(process: PTYProcess, bedrock: Bool) async throws {
        do {
            if bedrock {
                try await resumeSaveOnBedrock(process: process)
            } else {
                try await resumeSaveOnJava(process: process)
            }

            await stopProcess(process)
        } catch let error {
            await stopProcess(process)
            throw error
        }
    }

    private static func resumeSaveOnBedrock(process: PTYProcess) async throws {
        // Release Save Hold
        try process.sendLine("save resume")
        let saveResumeStrings = [
            "Changes to the level are resumed", // 1.17 and earlier
            "Changes to the world are resumed", // 1.18 and later
            "A previous save has not been completed"
        ]
        if await process.expect(saveResumeStrings, timeout: 60.0) == .noMatch {
            throw WorldBackupError.resumeFailed
        }
    }

    private static func resumeSaveOnJava(process: PTYProcess) async throws {
        try process.sendLine("save-on")
        if await process.expect(["Automatic saving is now enabled"], timeout: 60.0) == .noMatch {
            throw WorldBackupError.resumeFailed
        }
    }

    // Deprecated, as it only supports Bedrock
    public static func makeBackup(backupUrl: URL,
                                  dockerPath: String,
                                  containerName: String,
                                  worldsPath: URL) async throws {
        let process = try await pauseSaveOnServer(dockerPath: dockerPath, container: containerName, bedrock: true)

        do {
            Library.log.info("Starting Backup of worlds for: \(containerName))")
            for world in try World.getWorlds(at: worldsPath) {
                Library.log.info("Backing Up: \(world.name)")
                let backupWorld = try world.backup(to: backupUrl)
                Library.log.info("Backed up as: \(backupWorld.location.lastPathComponent)")
            }
            Library.log.info("Backups for \(containerName) Complete...")
        } catch let error {
            Library.log.error("\(error.localizedDescription)")
            Library.log.error("Backups for \(containerName) failed.")
        }

        try await resumeSaveOnServer(process: process, bedrock: true)
    }

    public static func fixOwnership(at folder: URL, config: BackupConfig.OwnershipConfig) throws {
        let (uid, gid) = try config.parseOwnerAndGroup()
        let (permissions) = try config.parsePosixPermissions()
        let backups = try getBackups(at: folder)
        for backup in backups.flatMap({ $1 }) {
            try backup.world.applyOwnership(owner: uid, group: gid, permissions: permissions)
        }
    }

    public static func trimBackups(at folder: URL, dryRun: Bool, trimDays: Int?, keepDays: Int?, minKeep: Int?) throws {
        let trimDays = trimDays ?? 3
        let keepDays = keepDays ?? 14
        let minKeep = minKeep ?? 1

        let deletingString = dryRun ? "Would Delete" : "Deleting"

        let backups = try WorldBackup.getBackups(at: folder)
        for (worldName, worldBackups) in backups {
            Library.log.debug("Processing: \(worldName)")
            let processedBackups = worldBackups.process(trimDays: trimDays, keepDays: keepDays, minKeep: minKeep)
            for processedBackup in processedBackups.filter({ $0.action == .trim }) {
                Library.log.info("\(deletingString): \(processedBackup.world.location.lastPathComponent)")
                if !dryRun {
                    do {
                        try FileManager.default.removeItem(at: processedBackup.world.location)
                    } catch {
                        Library.log.error("Unable to delete \(processedBackup.world.location)")
                    }
                }
            }
        }
    }

    static func getBackups(at folder: URL) throws -> [String: [WorldBackup]] {
        var results: [String: [WorldBackup]] = [:]

        let keys: [URLResourceKey] = [.contentModificationDateKey]

        let files = try FileManager.default.contentsOfDirectory(at: folder,
                                                                includingPropertiesForKeys: keys,
                                                                options: [])

        for possibleWorld in files {
            let resourceValues = try possibleWorld.resourceValues(forKeys: Set(keys))
            let modificationDate = resourceValues.contentModificationDate!
            if let world = try? World(url: possibleWorld) {
                var array = results[world.name] ?? []
                array.append(WorldBackup(world: world, date: modificationDate))
                results[world.name] = array
            }
        }

        return results
    }
}

extension Array where Element: WorldBackup {
    func trimBucket(keepLast count: Int = 1) {
        var keep: [Int] = []

        for (index, item) in self.enumerated() {
            if keep.count < count {
                keep.append(index)
                continue
            }

            for (keepIndex, keepItem) in keep.enumerated() {
                if self[keepItem].modificationDate < item.modificationDate {
                    keep[keepIndex] = index
                    self[keepItem].action = .trim
                    Library.log.debug("Ejecting \(self[keepItem].world.location.lastPathComponent) from keep list")
                } else {
                    Library.log.debug("Rejecting \(item.world.location.lastPathComponent) from keep list")
                    item.action = .trim
                }
            }
        }
    }

    func process(trimDays: Int, keepDays: Int, minKeep: Int) -> [WorldBackup] {
        let trimDays = DateComponents(day: -(trimDays - 1))
        let keepDays = DateComponents(day: -(keepDays - 1))
        let today = Calendar.current.date(from: Date().toDayComponents())!
        let trimDay = Calendar.current.date(byAdding: trimDays, to: today)!
        let keepDay = Calendar.current.date(byAdding: keepDays, to: today)!

        // Sort from oldest to newest first
        let modifiedBackups = self.sorted(by: { $0.modificationDate > $1.modificationDate })

        // Mark very old backups, but also bucket for trimming to dailies
        var buckets: [DateComponents: [WorldBackup]] = [:]
        for backup in modifiedBackups {
            if backup.modificationDate < keepDay {
                backup.action = .trim
            } else if backup.modificationDate < trimDay {
                let modificationDay = backup.modificationDate.toDayComponents()
                var bucket = buckets[modificationDay] ?? []
                bucket.append(backup)
                buckets[modificationDay] = bucket
            }
        }

        // Process Buckets
        for (_, bucket) in buckets {
            Library.log.debug("Trimming a Bucket")
            bucket.trimBucket()
        }

        // Go back and force any backups to be retained if required
        let keepCount = modifiedBackups.reduce(0, { $0 + ($1.action == .keep ? 1 : 0)})
        var forceKeepCount = Swift.min(modifiedBackups.count, Swift.max(minKeep - keepCount, 0))
        if forceKeepCount > 0 {
            for backup in modifiedBackups {
                if backup.action != .keep {
                    backup.action = .keep
                    forceKeepCount -= 1
                }
                if forceKeepCount <= 0 {
                    break
                }
            }
        }

        return modifiedBackups
    }
}
