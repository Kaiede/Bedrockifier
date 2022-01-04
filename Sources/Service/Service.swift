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
    enum ServiceError: Error {
        case noBackupInterval
        case noActiveTerminal
        case onlyOneIntervalTypeAllowed
    }

    private static let logger = Logger(label: "bedrockifier")

    let config: BackupConfig
    let environment: EnvironmentConfig
    let backupUrl: URL
    let dockerPath: String

    let healthFileUrl: URL

    var intervalTimer: ServiceTimer<String>?
    var containers: [ContainerConnection]

    init(config: BackupConfig, backupUrl: URL, dockerPath: String) {
        self.config = config
        self.environment = EnvironmentConfig()
        self.backupUrl = backupUrl
        self.dockerPath = dockerPath
        self.containers = []

        self.healthFileUrl = backupUrl.appendingPathComponent(".service_is_healthy")
    }

    public func run() throws {
        // Start the backups
        if let schedule = config.schedule {
            if schedule.interval != nil && schedule.daily != nil {
                BackupService.logger.error("Only 'interval' or 'daily' backup types are allowed. Not both.")
                throw ServiceError.onlyOneIntervalTypeAllowed
            }

            try connectContainers()

            if schedule.interval != nil {
                try startIntervalBackups()
            } else if schedule.daily != nil {
                try startDailyBackups()
            }

            if needsListeners() {
                startListenerBackups()
            }

            if let minInterval = try schedule.parseMinInterval() {
                BackupService.logger.info("Backup Minimum Interval is \(minInterval) seconds")
            }
        } else {
            // Without the schedule, we have to assume the docker container specifies an interval
            try connectContainers()
            try startIntervalBackups()
        }

        dispatchMain()
    }

    private func connectContainers() throws {
        containers = try ContainerConnection.loadContainers(from: config, dockerPath: dockerPath)

        // Attach to the containers
        if needsListeners() {
            for container in containers {
                try container.start()
            }
        }
    }

    func markHealthy() -> Bool {
        do {
            if !FileManager.default.fileExists(atPath: healthFileUrl.path) {
                try Data().write(to: healthFileUrl)
            }
            return true
        } catch let error {
            BackupService.logger.error("\(error.localizedDescription)")
            BackupService.logger.error("Unable to mark service as healthy.")
        }

        return false
    }

    private func needsListeners() -> Bool {
        return config.schedule?.onPlayerLogin == true || config.schedule?.onPlayerLogout == true || config.schedule?.onLastLogout == true
    }

    private func startIntervalBackups() throws {
        guard let interval = try getBackupInterval() else {
            BackupService.logger.error("Unable to Parse Backup Interval")
            throw ServiceError.noBackupInterval
        }

        BackupService.logger.info("Backup Interval: \(interval) seconds")
        let timer = ServiceTimer(identifier: "interval", queue: DispatchQueue.main)
        var startTime = Date()
        if let startupDelay = try getStartupDelay() {
            BackupService.logger.info("Delaying First Backup: \(startupDelay) seconds")
            startTime += startupDelay
        }
        timer.schedule(startingAt: startTime, repeating: .seconds(Int(interval)))
        timer.setHandler {
            await self.runFullBackup(isDaily: false)
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
            await self.runFullBackup(isDaily: true)

            guard let nextFiring = dayTime.calcNextDate(after: Date()) else {
                BackupService.logger.error("Unable to calculate next daily backup date")
                self.markUnhealthy()
                exit(1)
            }

            BackupService.logger.info("Next Backup: \(Library.dateFormatter.string(from: nextFiring))")
            timer.schedule(at: nextFiring)
        }

        self.intervalTimer = timer
    }

    private func startListenerBackups() {
        let playerNotifications = [
            "Player connected:",
            "Player disconnected:",
            "joined the game",
            "left the game"
        ]

        BackupService.logger.info("Starting Listeners for Containers")
        for container in containers {
            container.terminal.listen(for: playerNotifications) { content in
                Task {
                    await self.onListenerEvent(container: container, content: content)
                }
            }
        }
    }

    private func onListenerEvent(container: ContainerConnection, content: String) async {
        BackupService.logger.debug("Listener Event for \(container.name): \(content)")
   
        if content.contains("Player connected:") || content.contains("joined the game") {
            // Login event
            let playerCount = container.incrementPlayerCount()
            BackupService.logger.info("Player Logged In: \(container.name), Players Active: \(playerCount)")
            if config.schedule?.onPlayerLogin == true {
                await runSingleBackup(container: container)
            }
        }

        if content.contains("Player disconnected:") || content.contains("left the game") {
            // Logout event
            let playerCount = container.decrementPlayerCount()
            BackupService.logger.info("Player Logged Out: \(container.name), Players Active: \(playerCount)")
            if config.schedule?.onPlayerLogout == true {
                await runSingleBackup(container: container)
            } else if config.schedule?.onLastLogout == true && playerCount == 0 {
                await runSingleBackup(container: container)
            }
        }
    }

    private func runSingleBackup(container: ContainerConnection) async {
        guard shouldRunBackup(container: container) else {
            return
        }

        BackupService.logger.info("Running Single Backup for \(container.name)")
        do {
            try await container.runBackup(destination: backupUrl)
            try runPostBackupTasks()
            BackupService.logger.info("Single Backup Completed")
            _ = markHealthy()
        } catch let error {
            BackupService.logger.error("Single Backup for \(container.name) failed")
            BackupService.logger.error("\(error.localizedDescription)")
            markUnhealthy()
        }
    }

    private func runFullBackup(isDaily: Bool) async {
        BackupService.logger.info("Starting Full Backup")
        do {
            let needsListeners = needsListeners()
            for container in containers {
                guard shouldRunBackup(container: container) || isDaily else {
                    continue
                }

                if !needsListeners {
                    try container.start()
                }
                try await container.runBackup(destination: backupUrl)
                if !needsListeners {
                    await container.stop()
                }
            }

            try runPostBackupTasks()

            BackupService.logger.info("Full Backup Completed")

            if !needsListeners {
                for container in containers {
                    try container.reset()
                }
            }
            _ = markHealthy()
        } catch let error {
            BackupService.logger.error("\(error.localizedDescription)")
            BackupService.logger.error("Full Backup Failed")
            markUnhealthy()
        }
    }

    private func runPostBackupTasks() throws {
        if let ownershipConfig = config.ownership {
            BackupService.logger.info("Performing Ownership Fixup")
            try WorldBackup.fixOwnership(at: backupUrl, config: ownershipConfig)
        }

        if let trimJob = config.trim {
            BackupService.logger.info("Performing Trim Jobs")
            try WorldBackup.trimBackups(at: backupUrl,
                                        dryRun: false,
                                        trimDays: trimJob.trimDays,
                                        keepDays: trimJob.keepDays,
                                        minKeep: trimJob.minKeep)
        }
    }

    private func shouldRunBackup(container: ContainerConnection) -> Bool {
        if let minInterval = try? config.schedule?.parseMinInterval() {
            // Allow for some slop of a minute in the timing.
            let slop = 60.0
            let intervalWithSlop = max(0.0, minInterval - slop)
            BackupService.logger.debug("Checking Min Interval of \(minInterval), with slop: \(intervalWithSlop)")
            let now = Date()
            if container.lastBackup + intervalWithSlop > now {
                BackupService.logger.info("Skipping Backup, still within \(minInterval) seconds since last backup")
                return false
            }
        }

        return true
    }

    private func getBackupInterval() throws -> TimeInterval? {
        if let interval = try config.schedule?.parseInterval() {
            return interval
        }

        return try Bedrockifier.parse(interval: environment.backupInterval)
    }

    private func getStartupDelay() throws -> TimeInterval? {
        return try config.schedule?.parseStartupDelay()
    }

    private func markUnhealthy() {
        do {
            if FileManager.default.fileExists(atPath: healthFileUrl.path) {
                try FileManager.default.removeItem(at: healthFileUrl)
            }
        } catch let error {
            BackupService.logger.error("\(error.localizedDescription)")
            BackupService.logger.error("Unable to mark service as unhealthy.")
        }
    }
}
