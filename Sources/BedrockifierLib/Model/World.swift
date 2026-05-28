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
import ZIPFoundation

public struct World {
    public enum WorldType {
        case folder
        case mcworld
        case javaBackup

        init(url: URL) throws {
            if WorldType.isFolderWorld(url: url) {
                self = .folder
            } else if url.pathExtension == "mcworld" {
                self = .mcworld
            } else if url.pathExtension == "zip" {
                self = .javaBackup
            } else {
                throw WorldError.invalidUrl(url: url, innerError: WorldError.invalidWorldType)
            }
        }

        private static func isFolderWorld(url: URL) -> Bool {
            return checkBedrockFolder(url: url) || checkJavaFolder(url: url)
        }

        private static func checkBedrockFolder(url: URL) -> Bool {
            return FileManager.default.fileExists(atPath: url.appendingPathComponent("levelname.txt").path)
        }

        private static func checkJavaFolder(url: URL) -> Bool {
            return FileManager.default.fileExists(atPath: url.appendingPathComponent("level.dat").path)
        }
    }

    public let name: String
    public let type: WorldType
    public let location: URL
    public var size: UInt64 {
        do {
            let possibleSize = try FileManager.default.attributesOfItem(atPath: location.path)[.size]
            guard let size = possibleSize as? UInt64 else {
                return 0
            }

            return size
        } catch {
            return 0
        }
    }

    public init(url: URL) throws {
        self.type = try WorldType(url: url)
        self.location = url
        self.name = try World.fetchName(type: type, location: location)
    }

    private static func fetchName(type: WorldType, location: URL) throws -> String {
        switch type {
        case .folder:
            return try fetchFolderName(location: location)
        case .mcworld:
            return try fetchBedrockBackupName(location: location)
        case .javaBackup:
            return try fetchJavaBackupName(location: location)
        }
    }

    private static func fetchFolderName(location: URL) throws -> String {
        // Bedrock level name
        let levelNameFile = location.appendingPathComponent("levelname.txt")
        if FileManager.default.fileExists(atPath: levelNameFile.path) {
            do {
                return try String(contentsOf: location.appendingPathComponent("levelname.txt"))
            } catch {
                throw WorldError.invalidLevelNameFile
            }
        }

        // Java default also works for corrupted Bedrock situations.
        return location.lastPathComponent
    }

    private static func backupNameIsSanitary(_ name: String) -> Bool {
        let restrictedCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")

        return
            !name.isEmpty &&
            name.rangeOfCharacter(from: restrictedCharacters) == nil &&
            !name.contains("..")
    }

    private static func fetchBedrockBackupName(location: URL) throws -> String {
        let archive = try Archive(url: location, accessMode: .read)
        guard let levelnameEntry = archive["levelname.txt"] else {
            throw WorldError.missingLevelName
        }

        var result: String?
        _ = try archive.extract(levelnameEntry, consumer: { result = String(data: $0, encoding: .utf8) })

        guard let finalResult = result else {
            throw WorldError.missingLevelName
        }

        guard backupNameIsSanitary(finalResult) else {
            throw WorldError.invalidLevelName
        }

        return finalResult
    }

    private static func fetchJavaBackupName(location: URL) throws -> String {
        let archive = try Archive(url: location, accessMode: .read)
        guard let levelDat = archive.first(where: { $0.path.hasSuffix("level.dat") }) else {
            throw WorldError.invalidLevelArchive
        }

        guard let worldName = NSString(string: levelDat.path).pathComponents.first else {
            throw WorldError.missingLevelName
        }

        guard backupNameIsSanitary(worldName) else {
            throw WorldError.invalidLevelName
        }

        return worldName
    }
}

extension World {
    static let partialPackExt = "part"

    public func pack(to url: URL, progress: Progress? = nil) throws -> World {
        guard self.type == .folder else {
            throw WorldError.invalidWorldType
        }

        let targetFolder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(atPath: targetFolder.path,
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        // We want to write to a temporary file first.
        // Write it as: "Foo.mcworld.part" or "Foo.zip.part"
        let tempUrl = url.appendingPathExtension(World.partialPackExt)

        do {
            try with(scopedObject: try Archive(url: tempUrl, accessMode: .create)) { archive in
                if isBedrockFolder() {
                    try packBedrock(to: archive, progress: progress)
                } else {
                    try packJava(to: archive, progress: progress)
                }

                let packedCount = archive.count { _ in true }
                Library.log.trace("Archive contains \(packedCount) items.")
            }
        } catch is NullScopedObjectError {
            throw WorldError.archiveCreationFailed
        } catch let error {
            throw error
        }

        // With it packed successfully, rename it.
        do {
            try FileManager.default.moveItem(at: tempUrl, to: url)
        } catch let error {
            Library.log.error("Failed to move \(tempUrl.path) to \(url.path)")
            throw error
        }

        return try World(url: url)
    }

    private func packBedrock(to archive: Archive, progress: Progress? = nil) throws {
        let dirEnum = FileManager.default.enumerator(atPath: self.location.path)

        var fileCount = 0
        while let archiveItem = dirEnum?.nextObject() as? String {
            let fullItemUrl = URL(fileURLWithPath: archiveItem, relativeTo: self.location)
            try archive.addEntry(with: archiveItem, fileURL: fullItemUrl)
            fileCount += 1
        }

        Library.log.debug("Packaged \(fileCount) files into mcworld archive.")
    }

    func packJava(to archive: Archive, progress: Progress? = nil) throws {
        let dirEnum = FileManager.default.enumerator(atPath: self.location.path)

        var fileCount = 0
        let folderBase = NSString(string: self.location.lastPathComponent)
        while let archiveItem = dirEnum?.nextObject() as? String {
            let archivePath = String(folderBase.appendingPathComponent(archiveItem))
            let fullItemUrl = URL(fileURLWithPath: archiveItem, relativeTo: self.location)
            try archive.addEntry(with: archivePath, fileURL: fullItemUrl)
            fileCount += 1
        }

        Library.log.debug("Packaged \(fileCount) files into a zip archive.")
    }

    public func unpack(to url: URL, progress: Progress? = nil) throws -> World {
        switch self.type {
        case .mcworld:
            return try unpackBedrock(to: url, progress: progress)
        case .javaBackup:
            return try unpackJava(to: url, progress: progress)
        case .folder:
            throw WorldError.invalidWorldType
        }
    }

    private func unpackBedrock(to url: URL, progress: Progress? = nil) throws -> World {
        assert(self.type == .mcworld)

        let targetFolder = url.appendingPathComponent(self.name)
        try FileManager.default.createDirectory(atPath: targetFolder.path,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        try FileManager.default.unzipItem(at: self.location,
                                          to: targetFolder,
                                          skipCRC32: false,
                                          progress: progress,
                                          pathEncoding: .utf8)
        return try World(url: targetFolder)
    }

    private func unpackJava(to url: URL, progress: Progress? = nil) throws -> World {
        assert(self.type == .javaBackup)

        try FileManager.default.createDirectory(atPath: url.path,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        try FileManager.default.unzipItem(at: self.location,
                                          to: url,
                                          skipCRC32: false,
                                          progress: progress,
                                          pathEncoding: .utf8)

        let finalFolder = url.appendingPathComponent(self.name)
        return try World(url: finalFolder)
    }

    func backup(to folder: URL, prefixContainerName: String?) throws -> World {
        let timestamp = Date()
        let fileName = makeFilename(timestamp: timestamp, prefixContainerName: prefixContainerName)
        let targetFile = folder.appendingPathComponent(fileName)

        try FileManager.default.createDirectory(atPath: folder.path, withIntermediateDirectories: true, attributes: nil)

        if !FileManager.default.fileExists(atPath: self.location.path) {
            Library.log.warning("Source for backup does not exist.")
        }

        switch self.type {
        case .folder:
            return try self.pack(to: targetFile)
        case .mcworld:
            try FileManager.default.copyItem(at: self.location, to: targetFile)
            return try World(url: targetFile)
        case .javaBackup:
            try FileManager.default.copyItem(at: self.location, to: targetFile)
            return try World(url: targetFile)
        }
    }

    private func makeFilename(timestamp: Date, prefixContainerName: String?) -> String {
        let timestampString = DateFormatter.backupDateFormatter.string(from: timestamp)
        let backupExtension = fetchBackupExtension()
        let filename = "\(self.name).\(timestampString).\(backupExtension)"

        if let prefix = prefixContainerName {
            return "\(prefix).\(filename)"
        } else {
            return filename
        }
    }

    private func fetchBackupExtension() -> String {
        switch self.type {
        case .folder:
            if isBedrockFolder() {
                return "mcworld"
            }

            return "zip"
        case .mcworld:
            return self.location.pathExtension
        case .javaBackup:
            return self.location.pathExtension
        }
    }

    private func isBedrockFolder() -> Bool {
        let levelNameFile = location.appendingPathComponent("levelname.txt")
        if FileManager.default.fileExists(atPath: levelNameFile.path) {
            return true
        }

        return false
    }

    public func applyOwnership(
        owner: Platform.UserID?,
        group: Platform.GroupID?,
        permissions: Platform.Mode?
    ) throws {
        try applyOwnership(owner: owner, group: group, folderMode: permissions, fileMode: permissions)
    }

    public func applyOwnership(
        owner: Platform.UserID?,
        group: Platform.GroupID?,
        folderMode: Platform.Mode?,
        fileMode: Platform.Mode?
    ) throws {
        let path = self.location.path
        do {
            let uidStr = owner != nil ? owner!.description : "nil"
            let gidStr = group != nil ? group!.description : "nil"
            let folderPerms = folderMode != nil ? String(format: "%o", folderMode!) : "nil"
            let filePerms = fileMode != nil ? String(format: "%o", fileMode!) : "nil"
            Library.log.debug("Ownership Change: \(uidStr):\(gidStr) with perms \(folderPerms):\(filePerms) at \(path)")

            // Apply directly to the core node (folder or mcworld package)
            var isDirectory: ObjCBool = false
            let rootUrl = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                Library.log.trace("Processing \(path)")
                do {
                    let pathMode = isDirectory.boolValue ? folderMode : fileMode
                    try World.applyOwnership(to: path, owner: owner, group: group, permissions: pathMode)
                } catch {
                    throw WorldError.failedToApplyOwnership(url: rootUrl, error: error)
                }
            }

            // For folders, enumerate the children.
            // This can be expensive, but provided for completeness.
            if isDirectory.boolValue,
                let enumerator = FileManager.default.enumerator(
                    at: rootUrl,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: .skipsHiddenFiles
                ) {
                Library.log.trace("Starting Processing World Directory")
                for case let fileUrl as URL in enumerator {
                    Library.log.trace("Processing \(fileUrl.path())")
                    do {
                        let resourceValues = try fileUrl.resourceValues(forKeys: [.isDirectoryKey])
                        let pathMode = resourceValues.isDirectory == true ? folderMode : fileMode
                        try World.applyOwnership(to: fileUrl.path(), owner: owner, group: group, permissions: pathMode)
                    } catch {
                        throw WorldError.failedToApplyOwnership(url: fileUrl, error: error)
                    }
                }
                Library.log.trace("Completed Processing World Directory")
            }
        } catch let error {
            Library.log.error("Unable to set ownership/permissions on \(path)")
            throw error
        }
    }

    static func applyOwnership(
        to path: String,
        owner: Platform.UserID?,
        group: Platform.GroupID?,
        permissions: Platform.Mode?
    ) throws {
        if owner != nil || group != nil {
            do {
                try Platform.changeOwner(path: path, uid: owner, gid: group)
            } catch Platform.PlatformError.errno(let errno) {
                Library.log.error("Couldn't change owner on \(path)")
                throw WorldError.ownershipChangeFailure(errno: errno)
            }
        }

        if let permissions = permissions {
            do {
                try Platform.changePermissions(path: path, permissions: permissions)
            } catch Platform.PlatformError.errno(let errno) {
                Library.log.error("Couldn't change mode on \(path)")
                throw WorldError.ownershipChangeFailure(errno: errno)
            }
        }
    }
}

extension World {
    public static func getWorlds(at url: URL) throws -> [World] {
        var results: [World] = []

        let folders = try FileManager.default.contentsOfDirectory(atPath: url.path)
        for possibleWorld in folders {
            let worldPath = URL(fileURLWithPath: possibleWorld, relativeTo: url)
            if let world = try? World(url: worldPath) {
                results.append(world)
            }
        }

        return results
    }
}

extension World {
    enum WorldError: Error {
        case invalidWorldType
        case invalidUrl(url: URL, innerError: Error)
        case invalidLevelArchive
        case missingLevelName
        case invalidLevelName
        case invalidLevelNameFile
        case archiveCreationFailed
        case failedToApplyOwnership(url: URL, error: Error)
        case ownershipChangeFailure(errno: Int32)
        case permissionsChangeFailure(errno: Int32)
    }
}

extension World.WorldError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidWorldType:
            return "World isn't a zip file, mcworld file, or valid Minecraft world folder"
        case .invalidUrl(let url, let innerError):
            return "Unable to access world path at '\(url.path)': \(innerError)"
        case .invalidLevelArchive:
            return "World archive is not a valid zip or mcworld file"
        case .missingLevelName:
            return "Unable to determine name of the world"
        case .invalidLevelName:
            return "Level name contains prohibited strings"
        case .invalidLevelNameFile:
            return "Unable to read contents of levelname.txt"
        case .archiveCreationFailed:
            return "Failed to create file for archive"
        case .failedToApplyOwnership(let url, let innerError):
            return "Unable to apply ownership to file at '\(url.path)': \(innerError)"
        case .ownershipChangeFailure(let errno):
            return "Change owner returned POSIX error: \(errno)"
        case .permissionsChangeFailure(let errno):
            return "Change permissions returned POSIX error: \(errno)"
        }
    }
}
