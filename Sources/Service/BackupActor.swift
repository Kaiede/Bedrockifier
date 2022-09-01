//
//  File.swift
//  
//
//  Created by Alex Hadden on 3/12/22.
//

import Foundation
import Bedrockifier

actor BackupActor {
    let config: BackupConfig
    let backupUrl: URL
    let healthFileUrl: URL

    var containers: [ContainerConnection]

    private var currentBackup: Task<ContainerConnection, Never>?
    private var currentFullBackup: Task<Void, Never>?

    init(config: BackupConfig, destination: URL) {
        self.config = config
        self.backupUrl = destination
        self.healthFileUrl = destination.appendingPathComponent(".service_is_healthy")
        self.containers = []
    }

    public func backupContainer(container: ContainerConnection) async {
        // If we are already doing a full backup, our container is already being handled
        if let currentFullBackup = currentFullBackup {
            BackupService.logger.debug("Skipping backup of \(container.name) because a full backup is in progress")
            await currentFullBackup.value
            return
        }

        // If we are backing up a single container, then check to see if is backing up
        // this container or a different one.
        if let currentBackup = currentBackup {
            BackupService.logger.debug("Waiting for a current backup to complete before backing up \(container.name)")
            let otherContainer = await currentBackup.value
            if container.name == otherContainer.name {
                BackupService.logger.debug("Skipping backup of \(container.name) because a backup was just completed")
                return
            }
        }

        currentBackup = Task {
            await runSingleBackup(container: container)
            return container
        }

        let _ = await currentBackup?.value
        currentBackup = nil
    }

    public func backupAllContainers(isDaily: Bool) async {
        let backedUpContainer = await currentBackup?.value
        if let currentFullBackup = currentFullBackup {
            BackupService.logger.debug("Skipping a full backup because one is in progress")
            await currentFullBackup.value
            return
        }

        currentFullBackup = Task {
            await runFullBackup(isDaily: isDaily, skipContainer: backedUpContainer)
        }

        await currentFullBackup?.value
        currentFullBackup = nil
    }

    public func cleanupContainers() async {
        BackupService.logger.info("Checking for servers that might not be cleaned up")
        for container in containers {
            if container.isSaveHeld(destination: backupUrl) {
                Task {
                    BackupService.logger.info("\(container.name) is dirty, cleaning up")
                    do {
                        let wasRunning = container.isRunning
                        if !wasRunning {
                            try container.start()
                        }

                        BackupService.logger.info("Cleaning up old backups for \(container.name)")
                        try container.startRcon()
                        try await container.cleanupIncompleteBackup(destination: backupUrl)
                        await container.stopRcon()

                        if !wasRunning {
                            await container.stop()
                        }
                    } catch let error {
                        BackupService.logger.error("\(error.localizedDescription)")
                        BackupService.logger.error("Failed to clean up container \(container.name)")
                    }
                }
            }
        }
    }

    public func markHealthy(forceWrite: Bool = false) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: healthFileUrl.path) && forceWrite {
                try FileManager.default.removeItem(at: healthFileUrl)
            }

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

    public func markUnhealthy() {
        do {
            if FileManager.default.fileExists(atPath: healthFileUrl.path) {
                try FileManager.default.removeItem(at: healthFileUrl)
            }
        } catch let error {
            BackupService.logger.error("\(error.localizedDescription)")
            BackupService.logger.error("Unable to mark service as unhealthy.")
        }
    }


    private func runSingleBackup(container: ContainerConnection) async {
        guard shouldRunBackup(container: container) else {
            return
        }

        BackupService.logger.info("Running Single Backup for \(container.name)")
        do {
            try container.startRcon()
            try await container.runBackup(destination: backupUrl)
            await container.stopRcon()
            try runPostBackupTasks()
            BackupService.logger.info("Single Backup Completed")
            _ = markHealthy()
        } catch let error {
            BackupService.logger.error("Single Backup for \(container.name) failed")
            BackupService.logger.error("\(error.localizedDescription)")
            markUnhealthy()
        }
    }
    
    public func needsListeners() -> Bool {
        return config.schedule?.onPlayerLogin == true
        || config.schedule?.onPlayerLogout == true
        || config.schedule?.onLastLogout == true
    }

    public func update(containers: [ContainerConnection]) {
        self.containers = containers
    }

    private func runFullBackup(isDaily: Bool, skipContainer: ContainerConnection?) async {
        BackupService.logger.info("Starting Full Backup")
        let needsListeners = needsListeners()
        var failedContainers = 0
        for container in containers {
            do {
                guard skipContainer?.name != container.name else {
                    BackupService.logger.info("Skipping \(container.name) as it was just backed up")
                    continue
                }

                guard shouldRunBackup(container: container) || isDaily else {
                    continue
                }

                if !needsListeners {
                    try container.start()
                }

                try container.startRcon()
                try await container.runBackup(destination: backupUrl)
                await container.stopRcon()

                if !needsListeners {
                    await container.stop()
                }
            } catch let error {
                failedContainers += 1
                BackupService.logger.error("\(error.localizedDescription)")
                BackupService.logger.error("Container \(container.name) failed to backup properly")
            }
        }

        do {
            try runPostBackupTasks()

            BackupService.logger.info("Full Backup Completed")

            if !needsListeners {
                for container in containers {
                    try container.reset()
                }
            }

            if failedContainers > 0 {
                markUnhealthy()
            } else {
                _ = markHealthy()
            }
        } catch let error {
            BackupService.logger.error("\(error.localizedDescription)")
            BackupService.logger.error("Full Backup Failed")
            markUnhealthy()
        }
    }

    private func runPostBackupTasks() throws {
        if let ownershipConfig = config.ownership {
            BackupService.logger.info("Performing Ownership Fixup")
            try Backups.fixOwnership(at: backupUrl, config: ownershipConfig)
        }

        if let trimJob = config.trim {
            BackupService.logger.info("Performing Trim Jobs")
            try Backups.trimBackups(World.self,
                                    at: backupUrl,
                                    dryRun: false,
                                    trimDays: trimJob.trimDays,
                                    keepDays: trimJob.keepDays,
                                    minKeep: trimJob.minKeep)
            try Backups.trimBackups(ServerExtras.self,
                                    at: backupUrl,
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
}
