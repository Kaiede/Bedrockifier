import XCTest
@testable import Bedrockifier

fileprivate func makeTempDir() throws -> URL {
    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    return tempDirectory
}

final class WorldTests: XCTestCase {
    func testInvalidUrl() {
        let homePath = "\"\(FileManager.default.homeDirectoryForCurrentUser.path)\""
        let homeUrl = URL(fileURLWithPath: homePath)

        do {
            let _ = try World(url: homeUrl)
            XCTFail("Expected the call to throw")
        } catch World.WorldError.invalidUrl(let url, _) {
            XCTAssertEqual(url, homeUrl)
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testJavaFolder() {
        do {
            let folder = try makeTempDir()
            defer {
                do {
                    try FileManager.default.removeItem(at: folder)
                } catch {
                    XCTFail("\(error.localizedDescription)")
                }
            }

            let markerFile = folder.appendingPathComponent("level.dat")
            let didCreate = FileManager.default.createFile(atPath: markerFile.path, contents: Data())
            XCTAssertTrue(didCreate)

            let world = try World(url: folder)
            XCTAssertEqual(world.name, folder.lastPathComponent)
            XCTAssertEqual(world.type, .folder)
            XCTAssertEqual(world.location, folder)
        } catch {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testBedrockFolder() {
        do {
            let folder = try makeTempDir()
            defer {
                do {
                    try FileManager.default.removeItem(at: folder)
                } catch {
                    XCTFail("\(error.localizedDescription)")
                }
            }

            let markerFile = folder.appendingPathComponent("levelname.txt")
            let levelName = "Bedrock Level"
            guard let levelData = levelName.data(using: .utf8) else {
                XCTFail("Failed to convert string to data")
                return
            }
            let didCreate = FileManager.default.createFile(atPath: markerFile.path, contents: levelData)
            XCTAssertTrue(didCreate)

            let world = try World(url: folder)
            XCTAssertEqual(world.name, levelName)
            XCTAssertEqual(world.type, .folder)
            XCTAssertEqual(world.location, folder)
        } catch {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testBedrockArchiveUnpacksUsingTrimmedWorldName() throws {
        let source = try makeTempDir()
        let destination = try makeTempDir()
        let archive = source.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mcworld")

        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.removeItem(at: archive)
        }

        let markerFile = source.appendingPathComponent("levelname.txt")
        let levelName = "Trimmed Level\n"
        let didCreateLevelName = FileManager.default.createFile(atPath: markerFile.path, contents: Data(levelName.utf8))
        XCTAssertTrue(didCreateLevelName)

        let payloadFile = source.appendingPathComponent("payload.txt")
        let didCreatePayload = FileManager.default.createFile(atPath: payloadFile.path, contents: Data("restored".utf8))
        XCTAssertTrue(didCreatePayload)

        let packed = try World(url: source)
        XCTAssertEqual(packed.name, "Trimmed Level")

        _ = try packed.pack(to: archive)
        let unpacked = try World(url: archive).unpack(to: destination)

        XCTAssertEqual(unpacked.name, "Trimmed Level")
        XCTAssertEqual(unpacked.location.lastPathComponent, "Trimmed Level")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unpacked.location.appendingPathComponent("payload.txt").path))
    }

    func testFetchNameFailure() {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let testDirectory = tempDirectory.appendingPathComponent("fetchNameFailureTest", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            XCTFail("Unable to create test directory")
        }

        do {
            let levelNameFile = testDirectory.appendingPathComponent("levelname.txt", isDirectory: false)
            let data = Data([0xC2,0x01]) // Not valid UTF-8 Data
            try data.write(to: levelNameFile)
        } catch {
            XCTFail("Unable to write test data")
        }

        do {
            let _ = try World(url: testDirectory)
            XCTFail("Expected invalidLevelNameFile to be thrown")
        } catch World.WorldError.invalidLevelNameFile {
            // This is expected behavior
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }

        do {
            if FileManager.default.fileExists(atPath: testDirectory.path) {
                try FileManager.default.removeItem(at: testDirectory)
            }
        } catch {
            XCTFail("Unable to remove test directory")
        }
    }
}
