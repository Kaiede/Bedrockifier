import Foundation
import Testing
@testable import BedrockifierLib

@Suite struct ServerExtrasTests {
    @Test func invalidUrl() {
        let testPath = "/backups/Yosemite.Timestamp.zip"
        let testUrl = URL(fileURLWithPath: testPath)

        #expect(throws: ServerExtras.ServerExtrasError.self) {
            _ = try ServerExtras(url: testUrl)
        }
    }

    @Test func validUrl() throws {
        let testPath = "/backups/minecraft_cascades.extras.Timestamp.zip"
        let testUrl = URL(fileURLWithPath: testPath)

        let extras = try ServerExtras(url: testUrl)
        #expect(extras.name == "minecraft_cascades")
        #expect(extras.location == testUrl)
    }
}
