//
//  TrimCommant.swift
//  BackupTrimmer
//
//  Created by Alex Hadden on 4/5/21.
//

import ConsoleKit
import Foundation

public final class TrimCommand: Command {
    public struct Signature: CommandSignature {
        @Argument(name: "backupFolderPath", help: "Folder to Trim")
        var backupFolderPath: String
        
        @Option(name: "trimDays", short: "t", help: "How many days back to start trimming backups (default = 3)")
        var trimDays: Int?
        
        @Option(name: "keepDays", short: "k", help: "How many days back to keep any backups (default = 14)")
        var keepDays: Int?
        
        @Option(name: "minKeep", short: "m", help: "Minimum count of backups to keep for a single world (default = 1)")
        var minKeep: Int?
        
        @Flag(name: "dryRun", short: "n", help: "Don't delete, only perform a dry run")
        var dryRun: Bool
        
        public init() {}
    }
    
    public init() {}
    
    public var help: String {
        "Trims backups."
    }
    
    public func run(using context: CommandContext, signature: Signature) throws {
        let backupFolderUrl = URL(fileURLWithPath: signature.backupFolderPath, isDirectory: true)

        try WorldBackup.trimBackups(at: backupFolderUrl,
                                    dryRun: signature.dryRun,
                                    trimDays: signature.trimDays,
                                    keepDays: signature.keepDays,
                                    minKeep: signature.minKeep)
    }
}
