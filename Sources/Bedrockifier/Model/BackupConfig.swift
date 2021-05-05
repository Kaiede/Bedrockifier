//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import Foundation

struct BackupConfig: Codable {
    typealias ServerConfig = Dictionary<String, String>

    struct TrimConfig: Codable {
        var trimDays: Int?
        var keepDays: Int?
        var minKeep: Int?
    }
    
    var dockerPath: String?
    var backupPath: String?
    var servers: ServerConfig
    var trim: TrimConfig?
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
