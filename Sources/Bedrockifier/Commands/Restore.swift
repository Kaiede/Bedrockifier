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
        fileprivate static let terminal = Terminal()

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
            let environment = EnvironmentConfig()

            let configUri = getConfigFileUrl(environment: environment)
            guard FileManager.default.fileExists(atPath: configUri.path) else {
                Self.terminal.error("Configuration file doesn't exist at path \(configUri.path)")
                return
            }

            let config: BackupConfig
            do {
                config = try BackupConfig.getYaml(from: configUri)
            } catch {
                Self.terminal.error("Unable to read configuration file: \(error.localizedDescription)")
                return
            }

            let backupPath = self.backupPath ?? config.backupPath ?? environment.dataDirectory
            guard FileManager.default.fileExists(atPath: backupPath) else {
                Self.terminal.error("Backup folder not found at path \(backupPath)")
                return
            }
            let backupFolderUrl = URL(fileURLWithPath: backupPath, isDirectory: true)

            let targets = buildTargets(from: config)
            guard !targets.isEmpty else {
                Self.terminal.error("No containers were found in the configuration.")
                return
            }
            
            Self.terminal.output("Config: ".consoleText(.info) + configUri.path.consoleText())
            Self.terminal.output("Backups: ".consoleText(.info) + backupFolderUrl.path.consoleText())
            
            let target = chooseTarget(from: targets)
            guard !target.worlds.isEmpty else {
                Self.terminal.error("Container \(target.containerName) has no configured worlds.")
                return
            }

            let allBackups = try loadBackups(at: backupFolderUrl)
            let worldChoices = makeWorldChoices(for: target, allBackups: allBackups)

            guard !worldChoices.isEmpty else {
                Self.terminal.error("No backups were found for container \(target.containerName).")
                return
            }

            let worldChoice: (target: WorldTarget, backups: [Backup<World>])
            if worldChoices.count == 1 {
                worldChoice = worldChoices[0]
                Self.terminal.output("World: ".consoleText(.info) + worldChoice.target.worldName.consoleText())
            } else {
                let picked = Self.terminal.choose(
                    "Which world do you want to restore?",
                    from: worldChoices
                ) { entry in
                    "\(entry.target.worldName) — \(entry.backups.count) backup(s)".consoleText()
                }
                worldChoice = picked
            }

            let sortedBackups = worldChoice.backups.sorted(by: { $0.modificationDate > $1.modificationDate })
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium

            Self.terminal.emptyLine()
            let chosenBackup = Self.terminal.choose(
                "Which backup do you want to restore?",
                from: sortedBackups
            ) { backup in
                let timestamp = dateFormatter.string(from: backup.modificationDate)
                return "\(backup.item.location.lastPathComponent)  [\(timestamp)]".consoleText()
            }

            try restore(backup: chosenBackup, to: worldChoice.target)
        }

        private func chooseTarget(from targets: [RestoreTarget]) -> RestoreTarget {
            if let target = targets.first, targets.count == 1 {
                Self.terminal.output("Target: ".consoleText(.info) + "\(target.containerName) (\(target.displayKind))".consoleText())
                return target
            }
            
            Self.terminal.emptyLine()
            return Self.terminal.choose("Which container do you want to restore?", from: targets) { target in
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

        private func loadBackups(at folder: URL) throws -> [String: [Backup<World>]] {
            Self.terminal.emptyLine()
            let activity = Self.terminal.loadingBar(title: "Scanning backups")
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

        private func restore(backup: Backup<World>, to target: WorldTarget) throws {
            Self.terminal.output("Restore Summary", style: .info)
            Self.terminal.output("  Archive: ".consoleText(.info) + backup.item.location.path.consoleText())
            Self.terminal.output("  Target:  ".consoleText(.info) + target.destination.path.consoleText())
            Self.terminal.emptyLine()

            guard Self.terminal.confirm("This will overwrite the existing world. Continue?") else {
                Self.terminal.output("Restore cancelled.")
                return
            }

            let parentFolder = target.destination.deletingLastPathComponent()

            if FileManager.default.fileExists(atPath: target.destination.path) {
                let activity = Self.terminal.loadingBar(title: "Removing existing world")
                activity.start()
                do {
                    try FileManager.default.removeItem(at: target.destination)
                    activity.succeed()
                } catch {
                    activity.fail()
                    Self.terminal.error("Failed to remove existing world: \(error.localizedDescription)")
                    return
                }
            }

            let unpackedWorld: World
            let unpackActivity = Self.terminal.loadingBar(title: "Unpacking backup")
            unpackActivity.start()
            do {
                unpackedWorld = try backup.item.unpack(to: parentFolder)
                unpackActivity.succeed()
            } catch {
                unpackActivity.fail()
                Self.terminal.error("Failed to unpack backup: \(error.localizedDescription)")
                return
            }

            if unpackedWorld.location.path != target.destination.path {
                do {
                    try FileManager.default.moveItem(at: unpackedWorld.location, to: target.destination)
                } catch {
                    Self.terminal.error(
                        "Unpacked world is at \(unpackedWorld.location.path), but couldn't rename to \(target.destination.path): \(error.localizedDescription)"
                    )
                    return
                }
            }

            Self.terminal.emptyLine()
            Self.terminal.output("Restore complete.".consoleText(.success))
            Self.terminal.output("Restored to: ".consoleText(.info) + target.destination.path.consoleText())
        }

        private func getConfigFileUrl(environment: EnvironmentConfig) -> URL {
            if let configPath = self.configPath {
                return URL(fileURLWithPath: configPath)
            }

            let configDirectory = URL(fileURLWithPath: self.configFolder ?? environment.configDirectory)
            let defaultPath = configDirectory.appendingPathComponent(environment.configFile).path
            if FileManager.default.fileExists(atPath: defaultPath) {
                return URL(fileURLWithPath: defaultPath)
            }

            return configDirectory.appendingPathComponent(EnvironmentConfig.fallbackConfigFile)
        }
    }
}
