import Testing
@testable import BedrockifierLib

@Suite struct ListenerReconnectIntervalTests {
    @Test func yamlConfigSupportsListenerReconnectInterval() throws {
        let yaml = """
            backupPath: /backups
            servers:
                bedrock: /bedrock/worlds
            listenerReconnectInterval: 45s
            """

        let data = try #require(yaml.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.listenerReconnectInterval == "45s")
    }

    @Test func jsonConfigSupportsListenerReconnectInterval() throws {
        let json = """
            {
                "backupPath": "/backups",
                "servers": {
                    "bedrock": "/bedrock/worlds"
                },
                "listenerReconnectInterval": "2m"
            }
            """

        let data = try #require(json.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.listenerReconnectInterval == "2m")
    }

    @Test func listenerReconnectIntervalIsNilWhenMissing() throws {
        let json = """
            {
                "backupPath": "/backups",
                "servers": {
                    "bedrock": "/bedrock/worlds"
                }
            }
            """

        let data = try #require(json.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.listenerReconnectInterval == nil)
    }
}
