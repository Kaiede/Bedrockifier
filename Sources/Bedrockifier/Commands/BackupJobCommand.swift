//
//  File.swift
//
//
//  Created by Alex Hadden on 4/9/21.
//

import ConsoleKit
import Foundation

public final class BackupJobCommand: Command {
    public struct Signature: CommandSignature {
        @Argument(name: "configPath", help: "Path to the Backup Job Configuration")
        var configPath: String

        @Option(name: "dockerPath", help: "Path to docker")
        var dockerPath: String?

        @Option(name: "backupPath", help: "Folder to write backups to")
        var backupPath: String?

        public init() {}
    }

    public init() {}

    public var help: String {
        "Creates a backup of a bedrock server hosted in docker."
    }

    public func run(using context: CommandContext, signature: Signature) throws {
        let configUrl = URL(fileURLWithPath: signature.configPath)
        let config = try BackupConfig.getBackupConfig(from: configUrl)

        guard let backupPath = signature.backupPath ?? config.backupPath else {
            context.console.error("Backup path needs to be specified on command-line or config file")
            return
        }

        guard let dockerPath = signature.dockerPath ?? config.dockerPath else {
            context.console.error("Docker path needs to be specified on command-line or config file")
            return
        }

        let backupUrl = URL(fileURLWithPath: backupPath)

        print("Performing Backups")
        for (serverContainer, serverWorldsPath) in config.servers {
            let worldsUrl = URL(fileURLWithPath: serverWorldsPath)
            try WorldBackup.makeBackup(backupUrl: backupUrl,
                                       dockerPath: dockerPath,
                                       containerName: serverContainer,
                                       worldsPath: worldsUrl)
        }
        
        if let ownershipConfig = config.ownership {
            print("Performing Ownership Fixup")
            try WorldBackup.fixOwnership(at: backupUrl, config: ownershipConfig)
        }

        if let trimJob = config.trim {
            print("Performing Trim Jobs")
            try WorldBackup.trimBackups(at: backupUrl,
                                        dryRun: false,
                                        trimDays: trimJob.trimDays,
                                        keepDays: trimJob.keepDays,
                                        minKeep: trimJob.minKeep)
        }
    }
}
