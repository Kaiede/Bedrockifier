//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import Foundation

public struct BackupConfig: Codable {
    public typealias ServerConfig = [String: String]

    public struct TrimConfig: Codable {
        var trimDays: Int?
        var keepDays: Int?
        var minKeep: Int?
    }

    public struct OwnershipConfig: Codable {
        var chown: String?
        var permissions: String?
    }

    public var dockerPath: String?
    public var backupPath: String?
    public var servers: ServerConfig
    public var trim: TrimConfig?
    public var ownership: OwnershipConfig?
}

extension BackupConfig {
    public static func getBackupConfig(from url: URL) throws -> BackupConfig {
        let data = try Data(contentsOf: url)
        return try BackupConfig.getBackupConfig(from: data)
    }

    public static func getBackupConfig(from data: Data) throws -> BackupConfig {
        let decoder = JSONDecoder()
        return try decoder.decode(BackupConfig.self, from: data)
    }
}

extension BackupConfig.OwnershipConfig {
    func parseOwnerAndGroup() throws -> (UInt32?, UInt32?) {
        guard let chownString = self.chown else { return (nil, nil) }
        return try parse(ownership: chownString)
    }

    func parsePosixPermissions() throws -> UInt16? {
        guard let permissionsString = self.permissions else { return nil }
        return try parse(permissions: permissionsString)
    }
}
