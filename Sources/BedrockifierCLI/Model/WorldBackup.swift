//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import Foundation

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


extension WorldBackup {
    static func makeBackup(backupUrl: URL, containerName: String, worldsPath: URL) throws {
        let arguments: [String] = [
            "-c",
            "/usr/local/bin/docker attach --detach-keys=Q \(containerName)"
        ]
        
        // Attach To Container
        let process = ProcessWrapper(URL(fileURLWithPath: "/bin/sh"), arguments)
        process.launch()
        
        // Start Save Hold
        try process.send("save hold\n")
        let _ = try process.expect(["Saving", "The command is already running"])
        
        // Wait for files to be ready
        var waiting = true
        while waiting {
            try process.send("save query\n")
            let result = try process.expect(["Files are now ready to be copied", "A previous save has not been completed"])
            if result == "Files are now ready to be copied" { waiting = false }
        }
        
        // TODO: Perform Backup!
        print("Starting Backup of worlds at: \(worldsPath.path)")
        for world in try World.getWorlds(at: worldsPath) {
            print("Backing Up: \(world.name)")
            let backupWorld = try world.backup(to: backupUrl)
            print("Backed up as: \(backupWorld.location.lastPathComponent)")
        }
        print("Backup Complete...")
        
        // Release Save Hold
        try process.send("save resume\n")
        let _ = try process.expect("Changes to the level are resumed")
        
        // Detach from Container
        try process.send("Q")
        process.waitUntilExit()
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
    
    static func getBackups(at folder: URL) throws -> [String:[WorldBackup]] {
        var results: [String:[WorldBackup]] = [:]
        
        let keys: [URLResourceKey] = [.contentModificationDateKey]

        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
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
        var buckets: [DateComponents:[WorldBackup]] = [:]
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
