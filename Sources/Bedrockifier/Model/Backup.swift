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

enum BackupAction {
    case keep
    case trim
}

public protocol BackupItem {
    var name: String { get }
    var location: URL { get }

    init(url: URL) throws
}

protocol BackupProtocol: AnyObject {
    var action: BackupAction { get set }
    var modificationDate: Date { get }

    associatedtype Element: BackupItem
    var item: Element { get }
}

public class Backup<Element>: BackupProtocol where Element: BackupItem {
    var action: BackupAction = .keep
    let modificationDate: Date
    let item: Element

    init(item: Element, date: Date) {
        self.modificationDate = date
        self.item = item
    }
}

extension World: BackupItem {}

public struct Backups {
    public static func fixOwnership(at folder: URL, config: OwnershipConfig) throws {
        let (uid, gid) = try config.parseOwnerAndGroup()
        let (permissions) = try config.parsePosixPermissions()
        let backups = try getBackups(World.self, at: folder)
        for backup in backups.flatMap({ $1 }) {
            try backup.item.applyOwnership(owner: uid, group: gid, permissions: permissions)
        }
    }

    public static func trimBackups<ItemType>(
        _ type: ItemType.Type,
        at folder: URL,
        dryRun: Bool,
        trimDays: Int?,
        keepDays: Int?,
        minKeep: Int?
    ) throws where ItemType: BackupItem {
        let trimDays = trimDays ?? 3
        let keepDays = keepDays ?? 14
        let minKeep = minKeep ?? 1

        let deletingString = dryRun ? "Would Delete" : "Deleting"

        let backups = try getBackups(type, at: folder)
        for (worldName, worldBackups) in backups {
            Library.log.debug("Processing: \(worldName)")
            let processedBackups = try worldBackups.process(trimDays: trimDays, keepDays: keepDays, minKeep: minKeep)
            for processedBackup in processedBackups.filter({ $0.action == .trim }) {
                Library.log.info("\(deletingString): \(processedBackup.item.location.lastPathComponent)")
                if !dryRun {
                    do {
                        try FileManager.default.removeItem(at: processedBackup.item.location)
                    } catch {
                        Library.log.error("Unable to delete \(processedBackup.item.location)")
                    }
                }
            }
        }
    }

    static func getBackups<ItemType>(_ type: ItemType.Type, at folder: URL) throws -> [String: [Backup<ItemType>]] {
        var results: [String: [Backup<ItemType>]] = [:]

        let keys: [URLResourceKey] = [.contentModificationDateKey]

        let files = try FileManager.default.contentsOfDirectory(at: folder,
                                                                includingPropertiesForKeys: keys,
                                                                options: [])

        for possibleWorld in files {
            let resourceValues = try? possibleWorld.resourceValues(forKeys: Set(keys))
            guard let modificationDate = resourceValues?.contentModificationDate else {
                Library.log.error("Unable to get modification date for \(possibleWorld.path)")
                continue
            }

            if let item = try? ItemType(url: possibleWorld) {
                var array = results[item.name] ?? []
                array.append(Backup<ItemType>(item: item, date: modificationDate))
                results[item.name] = array
            }
        }

        return results
    }
}

extension Array where Element: BackupProtocol {
    func trimBucket(keepLast: Int = 1) {
        // Get any partial backups so they can be trimmed. Not worth keeping them around.
        let partialItems = self
            .filter({ $0.item.location.pathExtension.lowercased() == World.partialPackExt })
        // Sort in descending order so the keepers are at the front
        let items = self
            .filter({ $0.item.location.pathExtension.lowercased() != World.partialPackExt })
            .sorted(by: { $0.modificationDate > $1.modificationDate })

        guard keepLast < endIndex else { return }

        for item in partialItems {
            item.action = .trim
        }

        for item in items[keepLast ..< endIndex] {
            item.action = .trim
        }
    }

    func process(trimDays: Int, keepDays: Int, minKeep: Int) throws -> [Element] {
        let trimDays = DateComponents(day: -(trimDays - 1))
        let keepDays = DateComponents(day: -(keepDays - 1))

        guard let today = Calendar.current.date(from: Date().toDayComponents()) else {
            throw TrimmingError.failedToCalculateDate("today")
        }
        guard let trimDay = Calendar.current.date(byAdding: trimDays, to: today)  else {
            throw TrimmingError.failedToCalculateDate("trimDay")
        }
        guard let keepDay = Calendar.current.date(byAdding: keepDays, to: today)  else {
            throw TrimmingError.failedToCalculateDate("keepDay")
        }


        // Sort from oldest to newest first
        let modifiedBackups = self.sorted(by: { $0.modificationDate > $1.modificationDate })

        // Mark very old backups, but also bucket for trimming to dailies
        var buckets: [DateComponents: [Element]] = [:]
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
        for (bucketComponents, bucket) in buckets {
            Library.log.debug("Trimming a Bucket: \(bucketDateString(bucketComponents))")
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

    private func bucketDateString(_ dateComponents: DateComponents) -> String {
        let bucketDate = Calendar.current.nextDate(
            after: Date(),
            matching: dateComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .backward)
        if let realDate = bucketDate {
            return Library.dayFormatter.string(from: realDate)
        }

        return "<<UNKNOWN DATE>>"
    }
}

enum TrimmingError: Error {
    case failedToCalculateDate(String)
}

extension TrimmingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .failedToCalculateDate(let dateType):
            return "Could not calculate \(dateType) date for trimming"
        }
    }
}
