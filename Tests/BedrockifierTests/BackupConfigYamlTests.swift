import XCTest
@testable import Bedrockifier

final class BackupConfigYamlTests: XCTestCase {
    func testMinimalConfig() {
        guard let yamlData = minimalYamlConfigString.data(using: .utf8) else {
            XCTFail("couldn't get data for test YAML")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: yamlData)
            XCTAssertNil(config.backupPath)
            XCTAssertNil(config.dockerPath)
            XCTAssertEqual(config.servers?.count, 2)
            XCTAssertNil(config.trim)
            XCTAssertNil(config.loggingLevel)
        } catch(let error) {
            XCTFail("Unable to decode valid YAML: \(error)")
        }
    }

    func testMinimalConfigWithSpaces() {
        guard let yamlData = minimalYamlConfigWithSpacesString.data(using: .utf8) else {
            XCTFail("couldn't get data for test YAML")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: yamlData)
            XCTAssertNil(config.backupPath)
            XCTAssertNil(config.dockerPath)
            XCTAssertEqual(config.servers?.count, 2)
            XCTAssertNil(config.trim)
            XCTAssertNil(config.loggingLevel)
            XCTAssertEqual(config.servers?["bedrock_public"], "/bedrock public/worlds")
            XCTAssertEqual(config.servers?["bedrock_private"], "/bedrock private/worlds")
        } catch(let error) {
            XCTFail("Unable to decode valid YAML: \(error)")
        }
    }

    func testDockerConfig() {
        guard let yamlData = dockerYamlConfigString.data(using: .utf8) else {
            XCTFail("couldn't get data for test YAML")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: yamlData)
            XCTAssertNil(config.backupPath)
            XCTAssertNil(config.dockerPath)
            XCTAssertEqual(config.servers?.count, 2)
            XCTAssertNotNil(config.trim)
        } catch(let error) {
            XCTFail("Unable to decode valid YAML: \(error)")
        }
    }

    func testGoodConfig() {
        guard let yamlData = goodYamlConfigString.data(using: .utf8) else {
            XCTFail("couldn't get data for test YAML")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: yamlData)
            XCTAssertNotNil(config.backupPath)
            XCTAssertNotNil(config.dockerPath)
            XCTAssertEqual(config.servers?.count, 2)
            XCTAssertNotNil(config.trim)
            XCTAssertEqual(config.loggingLevel, .trace)
        } catch(let error) {
            XCTFail("Unable to decode valid YAML: \(error)")
        }
    }

    func testOwnershipConfig() {
        guard let yamlData = ownershipYamlConfigString.data(using: .utf8) else {
            XCTFail("couldn't get data for test YAML")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: yamlData)
            guard let ownershipConfig = config.ownership else {
                XCTFail("Ownership config missing.")
                return
            }

            let (uid, gid) = try ownershipConfig.parseOwnerAndGroup()
            let permissions = try ownershipConfig.parsePosixPermissions()
            XCTAssertEqual(uid, 100)
            XCTAssertEqual(gid, 200)
            XCTAssertEqual(permissions, 0o666)
        } catch(let error) {
            XCTFail("Unable to decode valid YAML: \(error)")
        }
    }

    func testScheduleConfig() {
        guard let yamlData = scheduleYamlConfigString.data(using: .utf8) else {
            XCTFail("couldn't get data for test YAML")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: yamlData)
            guard let scheduleConfig = config.schedule else {
                XCTFail("Schedule config missing.")
                return
            }

            XCTAssertEqual(scheduleConfig.interval, "3h")
            XCTAssertEqual(scheduleConfig.onPlayerLogin, true)
            XCTAssertEqual(scheduleConfig.onPlayerLogout, nil)
        } catch(let error) {
            XCTFail("Unable to decode valid YAML: \(error)")
        }
    }

    func testModernContainerPartialConfig() {
        guard let data = modernContainersPartialYamlConfigString.data(using: .utf8) else {
            XCTFail("couldn't get test data")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: data)

            XCTAssertNil(config.servers)
            XCTAssertNil(config.containers?.java)

            guard let bedrockContainers = config.containers?.bedrock else {
                XCTFail("Bedrock containers should decode")
                return
            }

            XCTAssertEqual(bedrockContainers.count, 1)
            XCTAssertEqual(bedrockContainers[0].name, "minecraft_bedrock")
            XCTAssertEqual(bedrockContainers[0].worlds, ["/bedrock/worlds/FirstWorld", "/bedrock/worlds/SecondWorld"])

        } catch(let error) {
            XCTFail("Unable to decode valid config: \(error)")
        }
    }

    func testModernContainerConfig() {
        guard let data = modernContainersYamlConfigString.data(using: .utf8) else {
            XCTFail("couldn't get test data")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: data)

            XCTAssertNil(config.servers)
            guard let javaContainers = config.containers?.java else {
                XCTFail("Java containers should decode")
                return
            }

            guard let bedrockContainers = config.containers?.bedrock else {
                XCTFail("Bedrock containers should decode")
                return
            }

            XCTAssertEqual(javaContainers.count, 1)
            XCTAssertEqual(javaContainers[0].name, "minecraft_java")
            XCTAssertEqual(javaContainers[0].worlds, ["/java/TheWorld"])


            XCTAssertEqual(bedrockContainers.count, 1)
            XCTAssertEqual(bedrockContainers[0].name, "minecraft_bedrock")
            XCTAssertEqual(bedrockContainers[0].worlds, ["/bedrock/worlds/FirstWorld", "/bedrock/worlds/SecondWorld"])

        } catch(let error) {
            XCTFail("Unable to decode valid config: \(error)")
        }
    }

    static var allTests = [
        ("testMinimalConfig", testMinimalConfig),
        ("testDockerConfig", testDockerConfig),
        ("testGoodConfig", testGoodConfig),
        ("testOwnershipConfig", testOwnershipConfig),
        ("testScheduleConfig", testScheduleConfig)
    ]
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
