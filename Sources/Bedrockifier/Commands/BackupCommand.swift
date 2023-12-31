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
import PTYKit

public final class BackupCommand: Command {
    public struct Signature: CommandSignature {
        @Argument(name: "dockerPath", help: "Path to docker")
        var dockerPath: String

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

        public init() {}
    }

    public init() {}

    public var help: String {
        "Creates a backup of a bedrock server hosted in docker."
    }

    public func run(using context: CommandContext, signature: Signature) throws {
        let group = DispatchGroup()
        var commandError: Error?
        let errorHandler = { error in
            commandError = error
        }

        Library.log.trace("Created Dispatch Group")

        runBackupTask(group: group, signature: signature, errorHandler: errorHandler)

        Library.log.trace("Waiting on Async Task")
        group.wait()

        if let commandError = commandError {
            throw commandError
        }

        Library.log.trace("Backup Job Complete")
    }

    private func runBackupTask(group: DispatchGroup, signature: Signature, errorHandler: @escaping (Error) -> Void) {
        group.enter()

        Task {
            do {
                Library.log.trace("Entered Async Task")

                Library.log.trace("Loading Configuration")
                // Configure Task
                let backupUrl = URL(fileURLWithPath: signature.outputFolderPath)
                let worldsPath = URL(fileURLWithPath: signature.worldsPath)
                let worlds = try World.getWorlds(at: worldsPath)
                let worldsPaths = worlds.map({ $0.location.path })
                let connection = try ContainerConnection(terminalPath: signature.dockerPath,
                                                         containerName: signature.containerName,
                                                         rconAddress: nil,
                                                         kind: .bedrock,
                                                         worlds: worldsPaths,
                                                         extras: nil)

                // Run Backup
                try connection.start()
                try await connection.runBackup(destination: backupUrl)
                await connection.stop()

                // Run optional trim
                if signature.trim {
                    try Backups.trimBackups(World.self,
                                            at: backupUrl,
                                            dryRun: false,
                                            trimDays: signature.keepDays,
                                            keepDays: signature.keepDays,
                                            minKeep: signature.minKeep)
                }
            } catch let error {
                Library.log.debug("\(error)")
                Library.log.error("\(error.localizedDescription)")
                Library.log.error("Backup Job Failed")
                errorHandler(error)
            }

            group.leave()
        }
    }
}
