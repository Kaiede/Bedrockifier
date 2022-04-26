import XCTest
@testable import Bedrockifier

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

    func testFolder() {
        do {
            let homeUrl = FileManager.default.homeDirectoryForCurrentUser
            let world = try World(url: homeUrl)

            XCTAssertEqual(world.name, homeUrl.lastPathComponent)
            XCTAssertEqual(world.type, .folder)
            XCTAssertEqual(world.location, homeUrl)
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
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
