//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import ConsoleKit
import Foundation

final class BackupCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "containerName", help: "Docker Container")
        var containerName: String

        @Argument(name: "worldsPath", help: "worlds folder of server")
        var worldsPath: String
        
        @Argument(name: "outputFolderPath", help: "Folder to write backups to")
        var outputFolderPath: String
                
        @Flag(name: "trim", short: "t", help: "Trim after backing up")
        var trim: Bool
        
        @Option(name: "trimDays", short: "t", help: "How many days back to start trimming backups (default = 3)")
        var trimDays: Int?
        
        @Option(name: "keepDays", short: "k", help: "How many days back to keep any backups (default = 14)")
        var keepDays: Int?
        
        @Option(name: "minKeep", short: "m", help: "Minimum count of backups to keep for a single world (default = 1)")
        var minKeep: Int?
        
        init() {}
    }
    
    var help: String {
        "Creates a backup of a bedrock server hosted in docker."
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
        let backupUrl = URL(fileURLWithPath: signature.outputFolderPath)
        let worldsPath = URL(fileURLWithPath: signature.worldsPath)
        try WorldBackup.makeBackup(backupUrl: backupUrl, containerName: signature.containerName, worldsPath: worldsPath)
        
        // Run optional trim
        if signature.trim {
            try WorldBackup.trimBackups(at: backupUrl, dryRun: false, trimDays: nil, keepDays: nil, minKeep: nil)
        }
    }
}
