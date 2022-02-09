import XCTest
@testable import Bedrockifier

final class ServerExtrasTests: XCTestCase {
    func testInvalidUrl() {
        let testPath = "/backups/Yosemite.Timestamp.zip"
        let testUrl = URL(fileURLWithPath: testPath)

        do {
            let _ = try ServerExtras(url: testUrl)
            XCTFail("Expected the call to throw")
        } catch ServerExtras.ServerExtrasError.invalidArchive(let url) {
            XCTAssertEqual(url, testUrl)
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testValidUrl() {
        let testPath = "/backups/minecraft_cascades.extras.Timestamp.zip"
        let testUrl = URL(fileURLWithPath: testPath)

        do {
            let extras = try ServerExtras(url: testUrl)

            XCTAssertEqual(extras.name, "minecraft_cascades")
            XCTAssertEqual(extras.location, testUrl)
        } catch ServerExtras.ServerExtrasError.invalidArchive(let url) {
            XCTFail("Expected this url to not throw: \(url.path)")
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }
}
