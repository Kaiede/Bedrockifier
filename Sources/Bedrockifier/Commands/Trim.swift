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

import Foundation

import ArgumentParser
import ConsoleKitTerminal

extension Bedrockifier {
    struct Trim: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "trim",
            abstract: "Trims backups."
        )

        @Argument(help: "Folder to Trim")
        var backupFolderPath: String

        @Option(name: .shortAndLong, help: "How many days back to start trimming backups (default = 3)")
        var trimDays: Int?

        @Option(name: .shortAndLong, help: "How many days back to keep any backups (default = 14)")
        var keepDays: Int?

        @Option(name: .shortAndLong, help: "Minimum count of backups to keep for a single world (default = 1)")
        var minKeep: Int?

        @Flag(name: [.customShort("n"), .long], help: "Don't delete, only perform a dry run")
        var dryRun: Bool = false

        func run() async throws {
            let terminal = initializeTerminal()
            let backupFolderUrl = URL(fileURLWithPath: backupFolderPath, isDirectory: true)
            terminal.output("Backup folder to trim: \(backupFolderUrl.path())")
            terminal.emptyLine()

            let activity = terminal.loadingBar(title: "Trimming Backups")
            do {
                activity.start()

                let trimAsk = Backups.Trim(
                    trimDays: trimDays,
                    keepDays: keepDays,
                    minKeep: minKeep
                )

                try Backups.trimBackups(
                    World.self,
                    at: backupFolderUrl,
                    dryRun: dryRun,
                    trim: trimAsk
                )
                try Backups.trimBackups(
                    ServerExtras.self,
                    at: backupFolderUrl,
                    dryRun: dryRun,
                    trim: trimAsk
                )

                activity.succeed()
            } catch {
                activity.fail()
                terminal.error("Failed to trim backups: \(error.localizedDescription)")
            }
        }
    }
}
