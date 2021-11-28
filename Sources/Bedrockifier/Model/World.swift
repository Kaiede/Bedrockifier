//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import Foundation
import ZIPFoundation

struct World {
    enum WorldError: Error {
        case invalidWorldType
        case invalidLevelArchive
        case missingLevelName
    }

    enum WorldType {
        case folder
        case mcworld

        init(url: URL) throws {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])

            if values.isDirectory == true {
                self = .folder
            } else if url.pathExtension == "mcworld" {
                self = .mcworld
            } else {
                throw WorldError.invalidWorldType
            }
        }
    }

    let name: String
    let type: WorldType
    let location: URL

    init(url: URL) throws {
        self.type = try WorldType(url: url)
        self.location = url
        self.name = try World.fetchName(type: type, location: location)
    }

    private static func fetchName(type: WorldType, location: URL) throws -> String {
        switch type {
        case .folder:
            return try String(contentsOf: location.appendingPathComponent("levelname.txt"))
        case .mcworld:
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
    }
}

extension World {
    func pack(to url: URL, progress: Progress? = nil) throws -> World {
        guard self.type == .folder else {
            throw WorldError.invalidWorldType
        }

        let targetFolder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(atPath: targetFolder.path,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        guard let archive = Archive(url: url, accessMode: .create) else {
            throw WorldError.invalidLevelArchive
        }

        let dirEnum = FileManager.default.enumerator(atPath: self.location.path)

        while let archiveItem = dirEnum?.nextObject() as? String {
            let fullItemUrl = URL(fileURLWithPath: archiveItem, relativeTo: self.location)
            try archive.addEntry(with: archiveItem, fileURL: fullItemUrl)
        }

        return try World(url: url)
    }

    func unpack(to url: URL, progress: Progress? = nil) throws -> World {
        guard self.type == .mcworld else {
            throw WorldError.invalidWorldType
        }

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

    func backup(to folder: URL) throws -> World {
        let timestamp = DateFormatter.backupDateFormatter.string(from: Date())
        let fileName = "\(self.name).\(timestamp).mcworld"
        let targetFile = folder.appendingPathComponent(fileName)

        try FileManager.default.createDirectory(atPath: folder.path, withIntermediateDirectories: true, attributes: nil)

        switch self.type {
        case .folder:
            return try self.pack(to: targetFile)
        case .mcworld:
            try FileManager.default.copyItem(at: self.location, to: targetFile)
            return try World(url: targetFile)
        }
    }
    
    func applyOwnership(owner: UInt?, group: UInt?) throws {
        let path = self.location.path
        var attributes: [FileAttributeKey: Any] = [:]
        if let owner = owner {
            attributes[.ownerAccountID] = NSNumber(value: owner)
        }
        if let group = group {
            attributes[.groupOwnerAccountID] = NSNumber(value: group)
        }
        
        // Apply directly to the core node (folder or mcworld package)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: path)
        }
        
        // For folders, enumerate the children.
        // This can be expensive, but provided for completeness.
        if isDirectory.boolValue, let subPaths = FileManager.default.subpaths(atPath: path) {
            for subPath in subPaths {
                try FileManager.default.setAttributes(attributes, ofItemAtPath: subPath)
            }
        }
    }
}

extension World {
    static func getWorlds(at url: URL) throws -> [World] {
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
