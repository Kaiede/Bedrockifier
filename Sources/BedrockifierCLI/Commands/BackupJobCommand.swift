//
//  File.swift
//
//
//  Created by Alex Hadden on 4/9/21.
//

import ConsoleKit
import Foundation

final class BackupJobCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "configPath", help: "Path to the Backup Job Configuration")
        var configPath: String
        
        init() {}
    }
    
    var help: String {
        "Creates a backup of a bedrock server hosted in docker."
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
        let configUrl = URL(fileURLWithPath: signature.configPath)
        let config = try BackupConfig.getBackupConfig(from: configUrl)
        
        print("Performing Backups")
        for server in config.servers {
            let backupUrl = URL(fileURLWithPath: server.backupPath)
            let worldsUrl = URL(fileURLWithPath: server.worldsPath)
            try WorldBackup.makeBackup(backupUrl: backupUrl, containerName: server.container, worldsPath: worldsUrl)
        }
        
        print("Performing Trim Jobs")
        for trimJob in config.trim {
            let trimBackupUrl = URL(fileURLWithPath: trimJob.backupPath)
            try WorldBackup.trimBackups(at: trimBackupUrl, dryRun: false, trimDays: trimJob.trimDays, keepDays: trimJob.keepDays, minKeep: trimJob.minKeep)
        }
    }
}
