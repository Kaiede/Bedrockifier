/*
 Bedrockifier

 Copyright (c) 2026 Adam Thayer
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
    struct Restore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "restore",
            abstract: "Interactively restores a backup archive over a configured server's world folder."
        )

        @Option(help: "Path to the config file")
        var configPath: String?

        @Option(name: .shortAndLong, help: "Folder to read config from")
        var configFolder: String?

        @Option(name: .shortAndLong, help: "Folder containing backups")
        var backupPath: String?

        @Flag(help: "Log debug level information")
        var debug = false

        @Flag(help: "Log trace level information, overriding --debug")
        var trace = false

        struct RestoreTarget {
            let containerName: String
            let kind: ContainerConnection.Kind
            let prefixContainerName: Bool
            let worlds: [URL]

            var displayKind: String {
                switch kind {
                case .bedrock: return "Bedrock"
                case .java: return "Java"
                }
            }
        }

        struct WorldTarget {
            let destination: URL
            let worldName: String
        }

        func run() async throws {
            let terminal = initializeTerminal()
            if trace {
                ConsoleKitLogger.logLevelOverride = .trace
                ConsoleKitLogger.showFilePosition = true
            } else if debug {
                ConsoleKitLogger.logLevelOverride = .debug
                ConsoleKitLogger.showFilePosition = true
            }

            let environment = EnvironmentConfig()
            var ownershipConfig = try OwnershipPosixConfig(
                ownership: environment.restoreOwner,
                mask: environment.restoreMask
            )

            let configUri = Bedrockifier.getConfigFileUrl(
                environment: environment,
                configPath: configPath,
                configFolder: configFolder
            )

            let config: BackupConfig
            do {
                config = try BackupConfig.getYaml(from: configUri)
            } catch {
                terminal.error("Unable to read configuration file from \(configUri.path()): \(error.localizedDescription)")
                return
            }

            let backupPath = self.backupPath ?? config.backupPath ?? environment.dataDirectory
            let backupFolderUrl = URL(fileURLWithPath: backupPath, isDirectory: true)

            let targets = buildTargets(from: config)
            guard !targets.isEmpty else {
                terminal.error("No containers were found in the configuration.")
                return
            }

            terminal.output("Config: ".consoleText(.info) + configUri.path.consoleText())
            terminal.output("Backups: ".consoleText(.info) + backupFolderUrl.path.consoleText())

            let target = chooseTarget(terminal: terminal, from: targets)
            guard !target.worlds.isEmpty else {
                terminal.error("Container \(target.containerName) has no configured worlds.")
                return
            }

            let allBackups = try loadBackups(terminal: terminal, at: backupFolderUrl)
            let worldChoices = makeWorldChoices(for: target, allBackups: allBackups)

            guard !worldChoices.isEmpty else {
                terminal.error("No backups were found for container \(target.containerName) as \(backupFolderUrl.path()).")
                return
            }

            let worldChoice: (target: WorldTarget, backups: [Backup<World>])
            if worldChoices.count == 1 {
                worldChoice = worldChoices[0]
                terminal.output("World: ".consoleText(.info) + worldChoice.target.worldName.consoleText())
            } else {
                let picked = terminal.choose(
                    "Which world do you want to restore?",
                    from: worldChoices
                ) { entry in
                    "\(entry.target.worldName) — \(entry.backups.count) backup(s)".consoleText()
                }
                worldChoice = picked
            }

            let sortedBackups = worldChoice.backups.sorted(by: { $0.modificationDate < $1.modificationDate })
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium

            terminal.emptyLine()
            let chosenBackup = terminal.choose(
                "Which backup do you want to restore?",
                from: sortedBackups
            ) { backup in
                let timestamp = dateFormatter.string(from: backup.modificationDate)
                return "\(backup.item.location.lastPathComponent)  [\(timestamp)]".consoleText()
            }


            let ownershipSource = pickOwnershipSource(worldUrl: worldChoice.target.destination)
            try ownershipConfig.fillEmptyOwner(from: ownershipSource)
            try ownershipConfig.fillEmptyModes(from: ownershipSource)
            try restore(terminal: terminal, backup: chosenBackup, to: worldChoice.target, ownership: ownershipConfig)
        }

        private func pickOwnershipSource(worldUrl: URL) -> URL {
            if FileManager.default.fileExists(atPath: worldUrl.path) {
                return worldUrl
            }

            return worldUrl.deletingLastPathComponent()
        }

        private func chooseTarget(terminal: Terminal, from targets: [RestoreTarget]) -> RestoreTarget {
            if let target = targets.first, targets.count == 1 {
                terminal.output("Target: ".consoleText(.info) + "\(target.containerName) (\(target.displayKind))".consoleText())
                return target
            }

            terminal.emptyLine()
            return terminal.choose("Which container do you want to restore?", from: targets) { target in
                "\(target.containerName) (\(target.displayKind))".consoleText()
            }
        }

        private func buildTargets(from config: BackupConfig) -> [RestoreTarget] {
            let prefixAll = config.prefixContainerName ?? false
            var targets: [RestoreTarget] = []

            for container in config.containers?.bedrock ?? [] {
                targets.append(RestoreTarget(
                    containerName: container.name,
                    kind: .bedrock,
                    prefixContainerName: container.prefixContainerName == true || prefixAll,
                    worlds: container.worlds.map { URL(fileURLWithPath: $0) }
                ))
            }

            for container in config.containers?.java ?? [] {
                targets.append(RestoreTarget(
                    containerName: container.name,
                    kind: .java,
                    prefixContainerName: container.prefixContainerName == true || prefixAll,
                    worlds: container.worlds.map { URL(fileURLWithPath: $0) }
                ))
            }

            for (containerName, worldsFolder) in config.servers ?? [:] {
                let worldsUrl = URL(fileURLWithPath: worldsFolder, isDirectory: true)
                let worldUrls = (try? World.getWorlds(at: worldsUrl).map({ $0.location })) ?? []
                targets.append(RestoreTarget(
                    containerName: containerName,
                    kind: .bedrock,
                    prefixContainerName: prefixAll,
                    worlds: worldUrls
                ))
            }

            return targets
        }

        private func loadBackups(terminal: Terminal, at folder: URL) throws -> [String: [Backup<World>]] {
            terminal.emptyLine()
            let activity = terminal.loadingBar(title: "Scanning backups")
            activity.start()
            do {
                let backups = try Backups.getBackups(World.self, at: folder)
                activity.succeed()
                return backups
            } catch {
                activity.fail()
                throw error
            }
        }

        private func makeWorldChoices(
            for target: RestoreTarget,
            allBackups: [String: [Backup<World>]]
        ) -> [(target: WorldTarget, backups: [Backup<World>])] {
            var results: [(target: WorldTarget, backups: [Backup<World>])] = []

            for worldUrl in target.worlds {
                let worldName = expectedWorldName(at: worldUrl)
                let candidateBackups = (allBackups[worldName] ?? []).filter { backup in
                    matchesContainer(backup: backup, target: target)
                }

                guard !candidateBackups.isEmpty else { continue }

                let entry = WorldTarget(destination: worldUrl, worldName: worldName)
                results.append((target: entry, backups: candidateBackups))
            }

            return results
        }

        private func expectedWorldName(at url: URL) -> String {
            if let world = try? World(url: url) {
                return world.name
            }
            return url.lastPathComponent
        }

        private func matchesContainer(backup: Backup<World>, target: RestoreTarget) -> Bool {
            guard target.prefixContainerName else {
                return true
            }
            return backup.item.location.lastPathComponent.hasPrefix("\(target.containerName).")
        }

        private func restore(terminal: Terminal, backup: Backup<World>, to target: WorldTarget, ownership: OwnershipPosixConfig) throws {
            terminal.output("Restore Summary", style: .info)
            terminal.output("  Archive: ".consoleText(.info) + backup.item.location.path.consoleText())
            terminal.output("  Target:  ".consoleText(.info) + target.destination.path.consoleText())
            terminal.emptyLine()

            if FileManager.default.fileExists(atPath: target.destination.path) {
                guard terminal.confirm("This will overwrite the existing world. Continue?") else {
                    terminal.output("Restore cancelled.")
                    return
                }

                terminal.emptyLine()
                let activity = terminal.loadingBar(title: "Removing existing world")
                activity.start()
                do {
                    try FileManager.default.removeItem(at: target.destination)
                    activity.succeed()
                } catch {
                    activity.fail()
                    terminal.error("Failed to remove existing world: \(error.localizedDescription)")
                    return
                }
            }

            let parentFolder = target.destination.deletingLastPathComponent()
            let unpackedWorld: World
            let unpackActivity = terminal.loadingBar(title: "Unpacking backup")
            unpackActivity.start()
            do {
                unpackedWorld = try backup.item.unpack(to: parentFolder)
                try unpackedWorld.applyOwnership(
                    owner: ownership.userId,
                    group: ownership.groupId,
                    folderMode: ownership.folderMode,
                    fileMode: ownership.fileMode
                )

                unpackActivity.succeed()
            } catch {
                unpackActivity.fail()
                terminal.error("Failed to unpack backup: \(error.localizedDescription)")
                return
            }

            if unpackedWorld.location.path != target.destination.path {
                do {
                    try FileManager.default.moveItem(at: unpackedWorld.location, to: target.destination)
                } catch {
                    terminal.error(
                        "Unpacked world is at \(unpackedWorld.location.path), but couldn't rename to \(target.destination.path): \(error.localizedDescription)"
                    )
                    return
                }
            }

            terminal.emptyLine()
            terminal.output("Restore complete.".consoleText(.success))
            terminal.output("Restored to: ".consoleText(.info) + target.destination.path.consoleText())
        }
    }
}
