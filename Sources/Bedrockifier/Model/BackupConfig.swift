//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import Foundation

struct BackupConfig: Codable {
    typealias ServerConfig = [String: String]

    struct TrimConfig: Codable {
        var trimDays: Int?
        var keepDays: Int?
        var minKeep: Int?
    }

    struct OwnershipConfig: Codable {
        var chown: String?
        var permissions: String?
    }

    var dockerPath: String?
    var backupPath: String?
    var servers: ServerConfig
    var trim: TrimConfig?
    var ownership: OwnershipConfig?
}

extension BackupConfig {
    static func getBackupConfig(from url: URL) throws -> BackupConfig {
        let data = try Data(contentsOf: url)
        return try BackupConfig.getBackupConfig(from: data)
    }

    static func getBackupConfig(from data: Data) throws -> BackupConfig {
        let decoder = JSONDecoder()
        return try decoder.decode(BackupConfig.self, from: data)
    }
}

extension BackupConfig.OwnershipConfig {
    func parseOwnerAndGroup() throws -> (UInt?, UInt?) {
        guard let chownString = self.chown else { return (nil, nil) }
        return try parse(ownership: chownString)
    }

    func parsePosixPermissions() throws -> UInt? {
        guard let permissionsString = self.permissions else { return nil }
        return try parse(permissions: permissionsString)
    }
}
