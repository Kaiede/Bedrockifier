//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import Foundation
import PTYKit

let usePty = false

class WorldBackup {
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

enum WorldBackupError: Error {
    case holdFailed
    case queryFailed
    case resumeFailed
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
                "-c",
                "\(dockerPath) attach --sig-proxy=false \(containerName)"
            ]
        }
    }
    
    static func makeBackup(backupUrl: URL, dockerPath: String, containerName: String, worldsPath: URL) throws {
        let arguments: [String] = getPtyArguments(dockerPath: dockerPath, containerName: containerName)

        // Attach To Container
        let process = try PTYProcess(URL(fileURLWithPath: "/bin/sh"), arguments: arguments)
        try process.run()

        defer {
            // Detach from Container
            if usePty {
                try? process.send("Q")
            } else {
                process.terminate()
            }
            process.waitUntilExit()
        }

        // Start Save Hold
        try process.sendLine("save hold")
        if process.expect(["Saving", "The command is already running"], timeout: 10.0) == .noMatch {
            throw WorldBackupError.holdFailed
        }

        // Wait for files to be ready
        var attemptLimit = 3
        while attemptLimit > 0 {
            try process.sendLine("save query")
            if process.expect("Files are now ready to be copied", timeout: 10.0) == .noMatch {
                attemptLimit -= 1
            } else {
                break
            }
        }

        if attemptLimit < 0 {
            throw WorldBackupError.queryFailed
        }

        do {
            print("Starting Backup of worlds at: \(worldsPath.path)")
            for world in try World.getWorlds(at: worldsPath) {
                print("Backing Up: \(world.name)")
                let backupWorld = try world.backup(to: backupUrl)
                print("Backed up as: \(backupWorld.location.lastPathComponent)")
            }
            print("Backup Complete...")
        } catch {
            print("Backup Failed...")
        }

        // Release Save Hold
        try process.sendLine("save resume")
        let saveResumeStrings = [
            "Changes to the level are resumed", // 1.17 and earlier
            "Changes to the world are resumed", // 1.18 and later
            "A previous save has not been completed"
        ]
        if process.expect(saveResumeStrings, timeout: 60.0) == .noMatch {
            throw WorldBackupError.resumeFailed
        }
    }

    static func fixOwnership(at folder: URL, config: BackupConfig.OwnershipConfig) throws {
        let (uid, gid) = try config.parseOwnerAndGroup()
        let (permissions) = try config.parsePosixPermissions()
        let backups = try getBackups(at: folder)
        for backup in backups.flatMap({ $1 }) {
            try backup.world.applyOwnership(owner: uid, group: gid, permissions: permissions)
        }
    }

    static func trimBackups(at folder: URL, dryRun: Bool, trimDays: Int?, keepDays: Int?, minKeep: Int?) throws {
        let trimDays = trimDays ?? 3
        let keepDays = keepDays ?? 14
        let minKeep = minKeep ?? 1

        let deletingString = dryRun ? "Would Delete" : "Deleting"

        let backups = try WorldBackup.getBackups(at: folder)
        for (worldName, worldBackups) in backups {
            print("Processing: \(worldName)")
            let processedBackups = worldBackups.process(trimDays: trimDays, keepDays: keepDays, minKeep: minKeep)
            for processedBackup in processedBackups.filter({ $0.action == .trim }) {
                print("\(deletingString): \(processedBackup.world.location.lastPathComponent)")
                if !dryRun {
                    do {
                        try FileManager.default.removeItem(at: processedBackup.world.location)
                    } catch {
                        print("Unable to delete \(processedBackup.world.location)")
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
                    print("Trimming \(self[keepItem].world.location.lastPathComponent)")
                } else {
                    print("Trimming \(item.world.location.lastPathComponent)")
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
            print("Trimming a Bucket")
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
