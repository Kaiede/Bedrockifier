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
import Logging
import PTYKit

import Bedrockifier

final class BackupService {
    struct Strings {
        static let bedrockLogin = "joined the game"
        static let bedrockLogout = "left the game"
        static let javaLogin = "Player connected:"
        static let javaLogout = "Player disconnected:"

        static let listenerStrings = [bedrockLogin, bedrockLogout, javaLogin, javaLogout]
        static let loginStrings = [bedrockLogin, javaLogin]
        static let logoutStrings = [bedrockLogout, javaLogout]
    }

    static let logger = Logger(label: "bedrockifier")
    private static let backupPriority = TaskPriority.background

    let config: BackupConfig
    let environment: EnvironmentConfig
    let dataUrl: URL
    let tools: ToolConfig
    let backupActor: BackupActor

    var intervalTimer: ServiceTimer<String>?

    init(config: BackupConfig, configUrl: URL, dataUrl: URL, tools: ToolConfig) {
        self.config = config
        self.environment = EnvironmentConfig()
        self.dataUrl = dataUrl
        self.tools = tools
        self.backupActor = BackupActor(config: config, configDir: configUrl, dataDir: dataUrl)
    }

    public func run() throws {
        Task {
            do {
                // Do startup validation
                try validateServerFolders()
                if await !backupActor.markHealthy(forceWrite: true) {
                    throw ServiceError.unableToMarkHealthy
                }

                // Do a startup delay if asked before attempting to connect to containers.
                // Delaying prior to connecting is required for rcon connections.
                if let startupDelay = try getStartupDelay() {
                    BackupService.logger.info("Delaying startup by: \(startupDelay) seconds")
                    try await Task.sleep(nanoseconds: UInt64(startupDelay * 1_000_000_000.0))
                }

                // Start the backups
                if let schedule = config.schedule {
                    if schedule.interval != nil && schedule.daily != nil {
                        BackupService.logger.error("Only 'interval' or 'daily' backup types are allowed. Not both.")
                        throw ServiceError.onlyOneIntervalTypeAllowed
                    }

                    try await connectContainers()
                    await self.backupActor.cleanupContainers()

                    if schedule.interval != nil || environment.backupInterval != nil {
                        try startIntervalBackups()
                    } else if schedule.daily != nil {
                        try startDailyBackups()
                    }

                    if await backupActor.needsListeners() {
                        await startListenerBackups()
                    }

                    if let minInterval = try schedule.parseMinInterval() {
                        BackupService.logger.info("Backup Minimum Interval is \(minInterval) seconds.")
                    }
                } else {
                    // Without the schedule, we have to assume the docker container specifies an interval
                    try await connectContainers()
                    try startIntervalBackups()
                }

                BackupService.logger.info("Service Started Successfully.")
            } catch {
                BackupService.logger.error("Encountered Error During Startup: \(error.localizedDescription)")
                BackupService.logger.trace("Error Details: \(error)")
                await MainActor.run {
                    exit(-1)
                }
            }

            if config.schedule?.runInitialBackup == true {
                BackupService.logger.info("Performing Initial Backup...")
                await self.backupActor.backupAllContainers(isDaily: true)
            }
        }

        dispatchMain()
    }

    private func connectContainers() async throws {
        let containers = try ContainerConnection.loadContainers(from: config, tools: tools)

        // Attach to the containers
        if await backupActor.needsListeners() {
            for container in containers {
                try await container.start()
            }
        }

        await self.backupActor.update(containers: containers)
    }

    private func validateServerFolders() throws {
        let bedrockWorlds = config.containers?.bedrock?.flatMap({ $0.worlds + ($0.extras ?? []) }) ?? []
        let javaWorlds = config.containers?.java?.flatMap({ $0.worlds + ($0.extras ?? []) }) ?? []
        let oldWorlds = config.servers?.values.map({ $0 }) ?? []

        let allWorlds: [String] = bedrockWorlds + javaWorlds + oldWorlds
        var failedWorlds: [String] = []
        for world in allWorlds where !FileManager.default.fileExists(atPath: world) {
            failedWorlds.append(world)
        }

        if failedWorlds.count > 0 {
            throw ServiceError.worldFoldersNotFound(failedWorlds)
        }
    }

    private func startIntervalBackups() throws {
        guard let interval = try getBackupInterval() else {
            BackupService.logger.error("Unable to Parse Backup Interval")
            throw ServiceError.noBackupInterval
        }

        BackupService.logger.info("Backup Interval: \(interval) seconds")
        let timer = ServiceTimer(identifier: "interval", queue: DispatchQueue.main)
        let startTime = Date()
        timer.schedule(startingAt: startTime, repeating: .seconds(Int(interval)))
        timer.setHandler(priority: BackupService.backupPriority) {
            await self.backupActor.backupAllContainers(isDaily: false)
        }

        self.intervalTimer = timer
    }

    private func startDailyBackups() throws {
        guard let dayTime = config.schedule?.daily else {
            BackupService.logger.error("Unable to Parse Daily Backup Time")
            throw ServiceError.noBackupInterval
        }

        BackupService.logger.info("Backup Time: \(dayTime)")
        let timer = ServiceTimer(identifier: "interval", queue: DispatchQueue.main)
        guard let firstFiring = dayTime.calcNextDate(after: Date()) else {
            BackupService.logger.error("Unable to calculate next daily backup date")
            throw ServiceError.noBackupInterval
        }

        BackupService.logger.info("Next Backup: \(Library.dateFormatter.string(from: firstFiring))")
        timer.schedule(at: firstFiring)
        timer.setHandler {
            await self.backupActor.backupAllContainers(isDaily: true)

            guard let nextFiring = dayTime.calcNextDate(after: Date()) else {
                BackupService.logger.error("Unable to calculate next daily backup date")
                await self.backupActor.markUnhealthy()
                exit(1)
            }

            BackupService.logger.info("Next Backup: \(Library.dateFormatter.string(from: nextFiring))")
            timer.schedule(at: nextFiring)
        }

        self.intervalTimer = timer
    }

    private func startListenerBackups() async {
        BackupService.logger.info("Starting Listeners for Containers")
        for container in await backupActor.containers {
            container.listen(for: Strings.listenerStrings) { content in
                Task(priority: BackupService.backupPriority) {
                    await self.onListenerEvent(container: container, content: content)
                }
            }
        }
    }

    private func onListenerEvent(container: ContainerConnection, content: String) async {
        BackupService.logger.debug("Listener Event for \(container.name): \(content)")

        if content.contains(oneOf: Strings.loginStrings) {
            // Login event
            let playerCount = container.incrementPlayerCount()
            BackupService.logger.info("Player Logged In: \(container.name), Players Active: \(playerCount)")
            if config.schedule?.onPlayerLogin == true {
                await self.backupActor.backupContainer(container: container)
            }
        }

        if content.contains(oneOf: Strings.logoutStrings) {
            // Logout event
            let playerCount = container.decrementPlayerCount()
            BackupService.logger.info("Player Logged Out: \(container.name), Players Active: \(playerCount)")
            if config.schedule?.onPlayerLogout == true {
                await self.backupActor.backupContainer(container: container)
            } else if config.schedule?.onLastLogout == true && playerCount == 0 {
                await self.backupActor.backupContainer(container: container)
            }
        }
    }

    private func getBackupInterval() throws -> TimeInterval? {
        if let interval = try config.schedule?.parseInterval() {
            return interval
        }

        if let interval = environment.backupInterval {
            return try Bedrockifier.parse(interval: interval)
        }

        return nil
    }

    private func getStartupDelay() throws -> TimeInterval? {
        return try config.schedule?.parseStartupDelay()
    }
}

extension BackupService {
    enum ServiceError: Error {
        case noBackupInterval
        case onlyOneIntervalTypeAllowed
        case worldFoldersNotFound([String])
        case unableToMarkHealthy
    }
}

extension BackupService.ServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noBackupInterval:
            return "No valid backup interval was able to be read from configuration or environment"
        case .onlyOneIntervalTypeAllowed:
            return "Only one of `interval` and `daily` are allowed"
        case .worldFoldersNotFound(let folders):
            let foldersString = folders.joined(separator: ", ")
            return "One or more folders weren't found: \(foldersString)"
        case .unableToMarkHealthy:
            return "Unable to write to backups folder"
        }
    }
}
