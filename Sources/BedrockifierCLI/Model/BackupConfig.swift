//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import Foundation

struct BackupConfig: Codable {
    struct ServerConfig: Codable {
        var container: String
        var worldsPath: String
    }

    struct TrimConfig: Codable {
        var trimDays: Int?
        var keepDays: Int?
        var minKeep: Int?
    }
    
    var dockerPath: String
    var backupPath: String
    var servers: [ServerConfig]
    var trim: [TrimConfig]
}


extension BackupConfig {
    static func getBackupConfig(from url: URL) throws -> BackupConfig {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: url)
        return try decoder.decode(BackupConfig.self, from: data)
    }
}
