import Testing
@testable import BedrockifierLib

@Suite struct BackupConfigJsonTests {
    @Test func minimalConfig() throws {
        let data = try #require(minimalJsonConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.backupPath == nil)
        #expect(config.dockerPath == nil)
        #expect(config.servers?.count == 2)
        #expect(config.trim == nil)
        #expect(config.loggingLevel == nil)
    }

    @Test func dockerConfig() throws {
        let data = try #require(dockerJsonConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.backupPath == nil)
        #expect(config.dockerPath == nil)
        #expect(config.servers?.count == 2)
        #expect(config.trim != nil)
    }

    @Test func goodConfig() throws {
        let data = try #require(goodJsonConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        #expect(config.backupPath != nil)
        #expect(config.dockerPath != nil)
        #expect(config.servers?.count == 2)
        #expect(config.trim != nil)
        #expect(config.loggingLevel == .debug)
    }

    @Test func ownershipConfig() throws {
        let data = try #require(ownershipJsonConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        let ownershipConfig = try #require(config.ownership)
        let (uid, gid) = try ownershipConfig.parseOwnerAndGroup()
        let permissions = try ownershipConfig.parsePosixPermissions()
        #expect(uid == 100)
        #expect(gid == 200)
        #expect(permissions == 0o666)
    }

    @Test func scheduleConfig() throws {
        let data = try #require(scheduleJsonConfigString.data(using: .utf8))
        let config = try BackupConfig.getYaml(from: data)
        let scheduleConfig = try #require(config.schedule)
        #expect(scheduleConfig.interval == "3h")
        #expect(scheduleConfig.onPlayerLogin == true)
        #expect(scheduleConfig.onPlayerLogout == nil)
    }

    @Test func modernContainerConfig() throws {
        let data = try #require(modernContainersJsonConfigString.data(using: .utf8))
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
}

// MARK: Test Data

let minimalJsonConfigString = """
    {
        "servers": {
            "bedrock_private": "/bedrock_private/worlds",
            "bedrock_public": "/bedrock_public/worlds"
        }
    }
    """

let dockerJsonConfigString = """
    {
        "servers": {
            "bedrock_private": "/bedrock_private/worlds",
            "bedrock_public": "/bedrock_public/worlds"
        },
        "trim": {
            "trimDays":   2,
            "keepDays":   14,
            "minKeep":    2
        }
    }
    """

let goodJsonConfigString = """
    {
        "dockerPath": "/usr/bin/docker",
        "backupPath": "/backups",
        "loggingLevel": "debug",
        "servers": {
            "bedrock_private": "/bedrock_private/worlds",
            "bedrock_public": "/bedrock_public/worlds"
        },
        "trim": {
            "trimDays":   2,
            "keepDays":   14,
            "minKeep":    2
        }
    }
    """

let ownershipJsonConfigString = """
    {
        "dockerPath": "/usr/bin/docker",
        "backupPath": "/backups",
        "servers": {
            "bedrock_private": "/bedrock_private/worlds",
            "bedrock_public": "/bedrock_public/worlds"
        },
        "ownership": {
            "chown": "100:200",
            "permissions": "666"
        },
        "trim": {
            "trimDays":   2,
            "keepDays":   14,
            "minKeep":    2
        }
    }
    """

let scheduleJsonConfigString = """
    {
        "dockerPath": "/usr/bin/docker",
        "backupPath": "/backups",
        "servers": {
            "bedrock_private": "/bedrock_private/worlds",
            "bedrock_public": "/bedrock_public/worlds"
        },
        "schedule": {
            "interval": "3h",
            "onPlayerLogin": true
        },
        "trim": {
            "trimDays":   2,
            "keepDays":   14,
            "minKeep":    2
        }
    }
    """

let modernContainersJsonConfigString = """
    {
        "dockerPath": "/usr/bin/docker",
        "backupPath": "/backups",
        "loggingLevel": "debug",
        "containers": {
            "bedrock": [
                {
                    "name": "minecraft_bedrock",
                    "worlds": [
                        "/bedrock/worlds/FirstWorld",
                        "/bedrock/worlds/SecondWorld"
                    ]
                }
            ],
            "java": [
                {
                    "name": "minecraft_java",
                    "worlds": [
                        "/java/TheWorld"
                    ]
                }
            ]
        },
        "trim": {
            "trimDays":   2,
            "keepDays":   14,
            "minKeep":    2
        }
    }
    """
