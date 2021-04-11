//
//  ScanCommand.swift
//  BackupTrimmer
//
//  Created by Alex Hadden on 4/5/21.
//

import ConsoleKit
import Foundation

let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.timeZone = Calendar.current.timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
}()


enum BackupAction {
    case keep
    case trim
    case delete
}

struct BackupItem {
    var action: BackupAction = .keep
    var modificationDate: Date
    var fileUrl: URL
    
    init(url: URL, date: Date) {
        self.modificationDate = date
        self.fileUrl = url
    }
}

extension BackupItem {
    var fileName: String {
        fileUrl.lastPathComponent
    }
}

struct DayBucket {
    var day: DateComponents
    var backupItems: [BackupItem] = []
    
    init(day: DateComponents) {
        self.day = day
    }
    
    mutating func trim(keepLast count: Int = 1) {
        var keep: [Int] = []
        
        for (index, item) in backupItems.enumerated() {
            if keep.count < count {
                keep.append(index)
                continue
            }
            
            for (keepIndex, keepItem) in keep.enumerated() {
                if backupItems[keepItem].modificationDate < item.modificationDate {
                    keep[keepIndex] = index
                    backupItems[keepItem].action = .trim
                }
            }
        }
    }
}

func process(backups: [BackupItem], trim: Int, keep: Int, context: CommandContext) -> [BackupItem] {
    let trimDays = DateComponents(day: -(trim - 1))
    let keepDays = DateComponents(day: -keep)
    let today = Calendar.current.date(from: Date().toDayComponents())!
    let trimDay = Calendar.current.date(byAdding: trimDays, to: today)!
    let keepDay = Calendar.current.date(byAdding: keepDays, to: today)!
    
    context.console.print("Trim Date: \(dateFormatter.string(from: trimDay))")
    context.console.print("Keep Date: \(dateFormatter.string(from: keepDay))")

    var buckets: [DateComponents:DayBucket] = [:]
    var results: [BackupItem] = []
    
    for item in backups {
        if item.modificationDate < keepDay {
            var modifiedItem = item
            modifiedItem.action = .delete
            results.append(modifiedItem)
        } else if item.modificationDate < trimDay {
            let modificationDay = item.modificationDate.toDayComponents()
            var bucket = buckets[modificationDay] ?? DayBucket(day: modificationDay)
            bucket.backupItems.append(item)
            buckets[modificationDay] = bucket
        } else {
            results.append(item)
        }
    }
    
    for bucket in buckets.values {
        var modifiedBucket = bucket
        modifiedBucket.trim()
        results.append(contentsOf: modifiedBucket.backupItems)
    }
    
    return results
}

func getBackupItems(backups: [URL]) -> [BackupItem] {
    backups.compactMap({
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: $0.path)
            guard let modificationDate = attributes[.modificationDate] as? Date else {
                return nil
            }
            
            return BackupItem(url: $0, date: modificationDate)
        } catch {
            return nil
        }
    })
}

func getModificationDates(backups: [URL]) -> [(String, Date)] {
    backups.compactMap({
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: $0.path)
            guard let modificationDate = attributes[.modificationDate] as? Date else {
                return nil
            }
            
            return ($0.lastPathComponent, modificationDate)
        } catch {
            return nil
        }
    })
}

final class ScanCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "backupFolderPath", help: "Folder to Scan")
        var backupFolderPath: String
        
        @Option(name: "trimdays", short: "t", help: "How many days back to start trimming backups (default = 2)")
        var trimDays: Int?
        
        @Option(name: "maxdays", short: "m", help: "How many days back to keep any backups (default = 14)")
        var maxDays: Int?
        
        init() {}
    }
    
    var help: String {
        "Scans backups without trimming them."
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
        let trimDays = signature.trimDays ?? 2
        let maxDays = signature.maxDays ?? 14

        let backupFolderUrl = URL(fileURLWithPath: signature.backupFolderPath, isDirectory: true)
        let backupFiles = try FileManager.default.contentsOfDirectory(atPath: backupFolderUrl.path)
        
        let backupUrls = backupFiles
            .filter({ $0.first != "." })
            .map({ backupFolderUrl.appendingPathComponent($0) })
        let backups = getBackupItems(backups: backupUrls)
        let actions = process(backups: backups, trim: trimDays, keep: maxDays, context: context)
        
        for backupFile in actions.sorted(by: { $0.modificationDate < $1.modificationDate }) {
            context.console.print("\(backupFile.fileName): \(backupFile.action) (\(dateFormatter.string(from: backupFile.modificationDate)))")
        }
    }
}
