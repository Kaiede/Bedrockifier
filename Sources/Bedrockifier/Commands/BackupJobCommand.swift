/*
 Bedrockifier

 Copyright (c) 2021 Adam Thayer
 Licensed under the MIT license, as follows:

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.)
 */

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

        Library.log.info("Performing Backups")
        for (serverContainer, serverWorldsPath) in config.servers {
            let worldsUrl = URL(fileURLWithPath: serverWorldsPath)
            try WorldBackup.makeBackup(backupUrl: backupUrl,
                                       dockerPath: dockerPath,
                                       containerName: serverContainer,
                                       worldsPath: worldsUrl)
        }
        
        if let ownershipConfig = config.ownership {
            Library.log.info("Performing Ownership Fixup")
            try WorldBackup.fixOwnership(at: backupUrl, config: ownershipConfig)
        }

        if let trimJob = config.trim {
            Library.log.info("Performing Trim Jobs")
            try WorldBackup.trimBackups(at: backupUrl,
                                        dryRun: false,
                                        trimDays: trimJob.trimDays,
                                        keepDays: trimJob.keepDays,
                                        minKeep: trimJob.minKeep)
        }
    }
}
