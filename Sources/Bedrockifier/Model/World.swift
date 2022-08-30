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
            let isDirectory = try WorldType.isDirectory(url: url)

            if isDirectory {
                self = .folder
            } else if url.pathExtension == "mcworld" {
                self = .mcworld
            } else if url.pathExtension == "zip" {
                self = .javaBackup
            } else {
                throw WorldError.invalidWorldType
            }
        }

        private static func isDirectory(url: URL) throws -> Bool {
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                return values.isDirectory == true
            } catch {
                throw WorldError.invalidUrl(url: url, innerError: error)
            }
        }
    }

    public let name: String
    public let type: WorldType
    public let location: URL

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

    private static func fetchBedrockBackupName(location: URL) throws -> String {
        guard let archive = Archive(url: location, accessMode: .read) else {
            throw WorldError.invalidLevelArchive
        }

        guard let levelnameEntry = archive["levelname.txt"] else {
            throw WorldError.missingLevelName
        }

        var result: String?
        _ = try archive.extract(levelnameEntry, consumer: { result = String(data: $0, encoding: .utf8) })

        guard let finalResult = result else {
            throw WorldError.missingLevelName
        }

        return finalResult
    }

    private static func fetchJavaBackupName(location: URL) throws -> String {
        guard let archive = Archive(url: location, accessMode: .read) else {
            throw WorldError.invalidLevelArchive
        }

        guard let levelDat = archive.first(where: { $0.path.hasSuffix("level.dat") }) else {
            throw WorldError.invalidLevelArchive
        }

        guard let worldName = NSString(string: levelDat.path).pathComponents.first else {
            throw WorldError.missingLevelName
        }

        return worldName
    }
}

extension World {
    static let partialPackExt = "part"

    func pack(to url: URL, progress: Progress? = nil) throws -> World {
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
            try with(scopedOptional: Archive(url: tempUrl, accessMode: .create)) { archive in
                if isBedrockFolder() {
                    try packBedrock(to: archive, progress: progress)
                } else {
                    try packJava(to: archive, progress: progress)
                }
            }
        } catch is NullScopedObjectError {
            throw WorldError.invalidLevelArchive
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

        while let archiveItem = dirEnum?.nextObject() as? String {
            let fullItemUrl = URL(fileURLWithPath: archiveItem, relativeTo: self.location)
            try archive.addEntry(with: archiveItem, fileURL: fullItemUrl)
        }
    }

    func packJava(to archive: Archive, progress: Progress? = nil) throws {
        let dirEnum = FileManager.default.enumerator(atPath: self.location.path)

        let folderBase = NSString(string: self.location.lastPathComponent)
        while let archiveItem = dirEnum?.nextObject() as? String {
            let archivePath = String(folderBase.appendingPathComponent(archiveItem))
            let fullItemUrl = URL(fileURLWithPath: archiveItem, relativeTo: self.location)
            try archive.addEntry(with: archivePath, fileURL: fullItemUrl)
        }
    }

    func unpack(to url: URL, progress: Progress? = nil) throws -> World {
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
                                          preferredEncoding: .utf8)
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
                                          preferredEncoding: .utf8)

        let finalFolder = url.appendingPathComponent(self.name)
        return try World(url: finalFolder)
    }

    func backup(to folder: URL) throws -> World {
        let timestamp = DateFormatter.backupDateFormatter.string(from: Date())
        let backupExtension = fetchBackupExtension()
        let fileName = "\(self.name).\(timestamp).\(backupExtension)"
        let targetFile = folder.appendingPathComponent(fileName)

        try FileManager.default.createDirectory(atPath: folder.path, withIntermediateDirectories: true, attributes: nil)

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

    func applyOwnership(owner: UInt32?, group: UInt32?, permissions: UInt16?) throws {
        let path = self.location.path
        do {
            let uidStr = owner != nil ? owner!.description : "nil"
            let gidStr = group != nil ? group!.description : "nil"
            let permsStr = permissions != nil ? String(format: "%o", permissions!) : "nil"
            Library.log.debug("Ownership Change: \(uidStr):\(gidStr) with perms \(permsStr) at \(path)")

            // Apply directly to the core node (folder or mcworld package)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                Library.log.trace("Processing \(path)")
                try World.applyOwnership(to: path, owner: owner, group: group, permissions: permissions)
            }

            // For folders, enumerate the children.
            // This can be expensive, but provided for completeness.
            if isDirectory.boolValue, let subPaths = FileManager.default.subpaths(atPath: path) {
                Library.log.trace("Starting Procesing Directory Childen")
                for subPath in subPaths {
                    Library.log.trace("Processing \(subPath)")
                    try World.applyOwnership(to: subPath, owner: owner, group: group, permissions: permissions)
                }
                Library.log.trace("Completed Processing Directory")
            }
        } catch let error {
            Library.log.error("Unable to set ownership/permissions on \(path)")
            throw error
        }
    }

    static func applyOwnership(to path: String, owner: UInt32?, group: UInt32?, permissions: UInt16?) throws {
        if owner != nil || group != nil {
            try Platform.changeOwner(path: path, uid: owner, gid: group)
        }

        if let permissions = permissions {
            try Platform.changePermissions(path: path, permissions: permissions)
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
        case invalidLevelNameFile
    }
}

extension World.WorldError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidWorldType: return "World isn't a zip file, mcworld file, or valid Minecraft world folder"
        case .invalidUrl(let url, let innerError): return "Unable to access world path at '\(url.path)': \(innerError)"
        case .invalidLevelArchive: return "World archive is not a valid zip or mcworld file"
        case .missingLevelName: return "Unable to determine name of the world"
        case .invalidLevelNameFile: return "Unable to read contents of levelname.txt"
        }
    }
}
