import Testing
@testable import BedrockifierLib

@Suite struct BackupConfigYamlTests {
    @Test func minimalConfig() throws {
        let data = try #require(minimalYamlConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.backupPath == nil)
        #expect(config.dockerPath == nil)
        #expect(config.servers?.count == 2)
        #expect(config.trim == nil)
        #expect(config.loggingLevel == nil)
    }

    @Test func minimalConfigWithSpaces() throws {
        let data = try #require(minimalYamlConfigWithSpacesString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.backupPath == nil)
        #expect(config.dockerPath == nil)
        #expect(config.servers?.count == 2)
        #expect(config.trim == nil)
        #expect(config.loggingLevel == nil)
        #expect(config.servers?["bedrock_public"] == "/bedrock public/worlds")
        #expect(config.servers?["bedrock_private"] == "/bedrock private/worlds")
    }

    @Test func dockerConfig() throws {
        let data = try #require(dockerYamlConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.backupPath == nil)
        #expect(config.dockerPath == nil)
        #expect(config.servers?.count == 2)
        #expect(config.trim != nil)
    }

    @Test func goodConfig() throws {
        let data = try #require(goodYamlConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.backupPath != nil)
        #expect(config.dockerPath != nil)
        #expect(config.servers?.count == 2)
        #expect(config.trim != nil)
        #expect(config.loggingLevel == .trace)
    }

    @Test func ownershipConfig() throws {
        let data = try #require(ownershipYamlConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        let ownershipConfig = try #require(config.ownership)
        let (uid, gid) = try ownershipConfig.parseOwnerAndGroup()
        let permissions = try ownershipConfig.parsePosixPermissions()
        #expect(uid == 100)
        #expect(gid == 200)
        #expect(permissions == 0o666)
    }

    @Test func scheduleConfig() throws {
        let data = try #require(scheduleYamlConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        let scheduleConfig = try #require(config.schedule)
        #expect(scheduleConfig.interval == "3h")
        #expect(scheduleConfig.onPlayerLogin == true)
        #expect(scheduleConfig.onPlayerLogout == nil)
    }

    @Test func modernContainerPartialConfig() throws {
        let data = try #require(modernContainersPartialYamlConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)

        #expect(config.servers == nil)
        #expect(config.containers?.java == nil)

        let bedrockContainers = try #require(config.containers?.bedrock)
        #expect(bedrockContainers.count == 1)
        #expect(bedrockContainers[0].name == "minecraft_bedrock")
        #expect(bedrockContainers[0].worlds == ["/bedrock/worlds/FirstWorld", "/bedrock/worlds/SecondWorld"])
    }

    @Test func modernContainerConfig() throws {
        let data = try #require(modernContainersYamlConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)

        #expect(config.servers == nil)
        let javaContainers = try #require(config.containers?.java)
        let bedrockContainers = try #require(config.containers?.bedrock)

        #expect(javaContainers.count == 1)
        #expect(javaContainers[0].name == "minecraft_java")
        #expect(javaContainers[0].worlds == ["/java/TheWorld"])

        #expect(bedrockContainers.count == 1)
        #expect(bedrockContainers[0].name == "minecraft_bedrock")
        #expect(bedrockContainers[0].worlds == ["/bedrock/worlds/FirstWorld", "/bedrock/worlds/SecondWorld"])
    }

    @Test func spacesInPathYamlConfig() throws {
        let data = try #require(spacesInPathYamlConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)

        #expect(config.servers == nil)
        let bedrockContainers = try #require(config.containers?.bedrock)

        #expect(bedrockContainers.count == 1)
        #expect(bedrockContainers[0].name == "minecraft_bedrock")
        #expect(bedrockContainers[0].worlds == ["/bedrock/worlds/First World", "/bedrock/worlds/Second World"])
    }
}

// MARK: Test Data

let minimalYamlConfigString = """
    servers:
       bedrock_private: /bedrock_private/worlds
       bedrock_public: /bedrock_public/worlds
    """

let minimalYamlConfigWithSpacesString = """
    servers:
       bedrock_private: "/bedrock private/worlds"
       bedrock_public: /bedrock public/worlds
    """

let dockerYamlConfigString = """
    servers:
        bedrock_private: /bedrock_private/worlds
        bedrock_public: /bedrock_public/worlds
    trim:
        trimDays: 2
        keepDays: 14
        minKeep: 2
    """

let goodYamlConfigString = """
    dockerPath: /usr/bin/docker
    backupPath: /backups
    loggingLevel: trace
    servers:
        bedrock_private: /bedrock_private/worlds
        bedrock_public: /bedrock_public/worlds
    trim:
        trimDays: 2
        keepDays: 14
        minKeep: 2
    """

let ownershipYamlConfigString = """
    dockerPath: /usr/bin/docker
    backupPath: /backups
    servers:
        bedrock_private: /bedrock_private/worlds
        bedrock_public: /bedrock_public/worlds
    ownership:
        chown: 100:200
        permissions: 666
    trim:
        trimDays: 2
        keepDays: 14
        minKeep: 2
    """

let scheduleYamlConfigString = """
    dockerPath: /usr/bin/docker
    backupPath: /backups
    servers:
        bedrock_private: /bedrock_private/worlds
        bedrock_public: /bedrock_public/worlds
    schedule:
        interval: 3h
        onPlayerLogin: true
    trim:
        trimDays: 2
        keepDays: 14
        minKeep: 2
    """

let modernContainersPartialYamlConfigString = """
    dockerPath: /usr/bin/docker
    backupPath: /backups
    loggingLevel: trace
    containers:
        bedrock:
            - name: minecraft_bedrock
              worlds:
                - /bedrock/worlds/FirstWorld
                - /bedrock/worlds/SecondWorld
    trim:
        trimDays: 2
        keepDays: 14
        minKeep: 2
    """

let modernContainersYamlConfigString = """
    dockerPath: /usr/bin/docker
    backupPath: /backups
    loggingLevel: trace
    containers:
        bedrock:
            - name: minecraft_bedrock
              worlds:
                - /bedrock/worlds/FirstWorld
                - /bedrock/worlds/SecondWorld
        java:
            - name: minecraft_java
              worlds:
                - /java/TheWorld
    trim:
        trimDays: 2
        keepDays: 14
        minKeep: 2
    """

let spacesInPathYamlConfigString = """
    dockerPath: /usr/bin/docker
    backupPath: /backups
    loggingLevel: trace
    containers:
        bedrock:
            - name: minecraft_bedrock
              worlds:
                - /bedrock/worlds/First World
                - "/bedrock/worlds/Second World"
    trim:
        trimDays: 2
        keepDays: 14
        minKeep: 2
    """
