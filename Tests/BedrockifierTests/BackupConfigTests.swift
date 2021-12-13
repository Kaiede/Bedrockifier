import XCTest
@testable import Bedrockifier

final class BackupConfigTests: XCTestCase {
    func testMinimalConfig() {
        guard let jsonData = minimalConfigString.data(using: .utf8) else {
            XCTFail("couldn't get data for test JSON")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: jsonData)
            XCTAssertNil(config.backupPath)
            XCTAssertNil(config.dockerPath)
            XCTAssertEqual(config.servers.count, 2)
            XCTAssertNil(config.trim)
        } catch(let error) {
            XCTFail("Unable to decode valid JSON: \(error)")
        }
    }

    func testDockerConfig() {
        guard let jsonData = dockerConfigString.data(using: .utf8) else {
            XCTFail("couldn't get data for test JSON")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: jsonData)
            XCTAssertNil(config.backupPath)
            XCTAssertNil(config.dockerPath)
            XCTAssertEqual(config.servers.count, 2)
            XCTAssertNotNil(config.trim)
        } catch(let error) {
            XCTFail("Unable to decode valid JSON: \(error)")
        }
    }

    func testGoodConfig() {
        guard let jsonData = goodConfigString.data(using: .utf8) else {
            XCTFail("couldn't get data for test JSON")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: jsonData)
            XCTAssertNotNil(config.backupPath)
            XCTAssertNotNil(config.dockerPath)
            XCTAssertEqual(config.servers.count, 2)
            XCTAssertNotNil(config.trim)
        } catch(let error) {
            XCTFail("Unable to decode valid JSON: \(error)")
        }
    }
    
    func testOwnershipConfig() {
        guard let jsonData = ownershipConfigString.data(using: .utf8) else {
            XCTFail("couldn't get data for test JSON")
            return
        }

        do {
            let config = try BackupConfig.getBackupConfig(from: jsonData)
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
            XCTFail("Unable to decode valid JSON: \(error)")
        }
    }

    static var allTests = [
        ("testMinimalConfig", testMinimalConfig),
        ("testDockerConfig", testDockerConfig),
        ("testGoodConfig", testGoodConfig),
        ("testOwnershipConfig", testOwnershipConfig),
    ]
}

// MARK: Test Data

let minimalConfigString = """
    {
        "servers": {
            "bedrock_private": "/bedrock_private/worlds",
            "bedrock_public": "/bedrock_public/worlds"
        }
    }
    """

let dockerConfigString = """
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

let goodConfigString = """
    {
        "dockerPath": "/usr/bin/docker",
        "backupPath": "/backups",
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

let ownershipConfigString = """
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
