import Foundation
import Testing
import ZIPFoundation
@testable import Bedrockifier

private func makeTempDir() throws -> URL {
    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    return tempDirectory
}

// Creates a .mcworld archive whose levelname.txt contains the given string.
private func makeBedrockArchive(levelName: String) throws -> (tempDir: URL, archive: URL) {
    let tempDir = try makeTempDir()
    let levelNameFile = tempDir.appendingPathComponent("levelname.txt")
    try (levelName.data(using: .utf8) ?? Data()).write(to: levelNameFile)

    let archiveURL = tempDir.appendingPathComponent("test.mcworld")
    let archive = try Archive(url: archiveURL, accessMode: .create)
    try archive.addEntry(with: "levelname.txt", fileURL: levelNameFile)
    return (tempDir, archiveURL)
}

// Creates a .zip archive with a single level.dat entry at the given path inside the ZIP.
private func makeJavaArchive(levelDatPath: String) throws -> (tempDir: URL, archive: URL) {
    let tempDir = try makeTempDir()
    let levelDatFile = tempDir.appendingPathComponent("level.dat")
    try Data([0]).write(to: levelDatFile)

    let archiveURL = tempDir.appendingPathComponent("test.zip")
    let archive = try Archive(url: archiveURL, accessMode: .create)
    try archive.addEntry(with: levelDatPath, fileURL: levelDatFile)
    return (tempDir, archiveURL)
}

@Suite struct WorldTests {
    @Test func invalidUrl() {
        let homePath = "\"\(FileManager.default.homeDirectoryForCurrentUser.path)\""
        let homeUrl = URL(fileURLWithPath: homePath)

        #expect {
            try World(url: homeUrl)
        } throws: { error in
            guard case World.WorldError.invalidUrl(let url, _) = error else { return false }
            return url == homeUrl
        }
    }

    @Test func javaFolder() throws {
        let folder = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: folder) }

        let markerFile = folder.appendingPathComponent("level.dat")
        let didCreate = FileManager.default.createFile(atPath: markerFile.path, contents: Data())
        #expect(didCreate)

        let world = try World(url: folder)
        #expect(world.name == folder.lastPathComponent)
        #expect(world.type == .folder)
        #expect(world.location == folder)
    }

    @Test func bedrockFolder() throws {
        let folder = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: folder) }

        let markerFile = folder.appendingPathComponent("levelname.txt")
        let levelName = "Bedrock Level"
        let levelData = try #require(levelName.data(using: .utf8))
        let didCreate = FileManager.default.createFile(atPath: markerFile.path, contents: levelData)
        #expect(didCreate)

        let world = try World(url: folder)
        #expect(world.name == levelName)
        #expect(world.type == .folder)
        #expect(world.location == folder)
    }

    // MARK: - Path Traversal (Bedrock .mcworld)

    @Test func bedrockBackupValidName() throws {
        let (tempDir, archiveURL) = try makeBedrockArchive(levelName: "My World")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let world = try World(url: archiveURL)
        #expect(world.name == "My World")
    }

    @Test func bedrockBackupDotDotName() throws {
        let (tempDir, archiveURL) = try makeBedrockArchive(levelName: "..")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect {
            try World(url: archiveURL)
        } throws: { error in
            if case World.WorldError.invalidLevelName = error { return true }
            return false
        }
    }

    @Test func bedrockBackupSlashTraversalName() throws {
        let (tempDir, archiveURL) = try makeBedrockArchive(levelName: "../../etc/passwd")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect {
            try World(url: archiveURL)
        } throws: { error in
            if case World.WorldError.invalidLevelName = error { return true }
            return false
        }
    }

    @Test func bedrockBackupBackslashName() throws {
        let (tempDir, archiveURL) = try makeBedrockArchive(levelName: "..\\..\\windows\\system32")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect {
            try World(url: archiveURL)
        } throws: { error in
            if case World.WorldError.invalidLevelName = error { return true }
            return false
        }
    }

    @Test func bedrockBackupEmptyName() throws {
        let (tempDir, archiveURL) = try makeBedrockArchive(levelName: "")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect {
            try World(url: archiveURL)
        } throws: { error in
            if case World.WorldError.invalidLevelName = error { return true }
            return false
        }
    }

    // MARK: - Path Traversal (Java .zip)

    @Test func javaBackupValidPath() throws {
        let (tempDir, archiveURL) = try makeJavaArchive(levelDatPath: "worldname/level.dat")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let world = try World(url: archiveURL)
        #expect(world.name == "worldname")
    }

    @Test func javaBackupDotDotPath() throws {
        let (tempDir, archiveURL) = try makeJavaArchive(levelDatPath: "../evil/level.dat")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect {
            try World(url: archiveURL)
        } throws: { error in
            if case World.WorldError.invalidLevelName = error { return true }
            return false
        }
    }

    @Test func javaBackupDeepTraversalPath() throws {
        let (tempDir, archiveURL) = try makeJavaArchive(levelDatPath: "../../etc/level.dat")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect {
            try World(url: archiveURL)
        } throws: { error in
            if case World.WorldError.invalidLevelName = error { return true }
            return false
        }
    }

    // MARK: -

    @Test func fetchNameFailure() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let testDirectory = tempDirectory.appendingPathComponent("fetchNameFailureTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true, attributes: nil)

        let levelNameFile = testDirectory.appendingPathComponent("levelname.txt", isDirectory: false)
        let data = Data([0xC2, 0x01]) // Not valid UTF-8 Data
        try data.write(to: levelNameFile)

        #expect {
            try World(url: testDirectory)
        } throws: { error in
            if case World.WorldError.invalidLevelNameFile = error { return true }
            return false
        }
    }
}
