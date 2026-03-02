import XCTest
@testable import Bedrockifier

final class ListenerReconnectIntervalTests: XCTestCase {
    func testYamlConfigSupportsListenerReconnectInterval() throws {
        let yaml = """
            backupPath: /backups
            servers:
                bedrock: /bedrock/worlds
            listenerReconnectInterval: 45s
            """

        let data = try XCTUnwrap(yaml.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)

        XCTAssertEqual(config.listenerReconnectInterval, "45s")
    }

    func testJsonConfigSupportsListenerReconnectInterval() throws {
        let json = """
            {
                "backupPath": "/backups",
                "servers": {
                    "bedrock": "/bedrock/worlds"
                },
                "listenerReconnectInterval": "2m"
            }
            """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)

        XCTAssertEqual(config.listenerReconnectInterval, "2m")
    }

    func testListenerReconnectIntervalIsNilWhenMissing() throws {
        let json = """
            {
                "backupPath": "/backups",
                "servers": {
                    "bedrock": "/bedrock/worlds"
                }
            }
            """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)

        XCTAssertNil(config.listenerReconnectInterval)
    }
}
