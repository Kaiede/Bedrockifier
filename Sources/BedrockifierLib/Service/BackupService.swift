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

import AsyncAlgorithms
import Hummingbird
import Logging
import PTYKit

public final class BackupService {
    struct Strings {
        static let bedrockLogin = "joined the game"
        static let bedrockLogout = "left the game"
        static let javaLogin = "Player connected:"
        static let javaLogout = "Player disconnected:"

        static let listenerStrings = [bedrockLogin, bedrockLogout, javaLogin, javaLogout]
        static let loginStrings = [bedrockLogin, javaLogin]
        static let logoutStrings = [bedrockLogout, javaLogout]
    }

    typealias ServiceContext = BasicRequestContext

    private static let defaultSleepInterval = Duration.seconds(600)
    public static let logger = Logger(label: "bedrockifier.service")
    private static let backupPriority = TaskPriority.background

    let config: BackupConfig
    let environment: EnvironmentConfig
    let dataUrl: URL
    let tools: ToolConfig
    let backupActor: BackupActor
    let httpTokenFile: URL

    public init(config: BackupConfig, configDir: URL, dataUrl: URL, tools: ToolConfig) {
        self.config = config
        self.environment = EnvironmentConfig()
        self.dataUrl = dataUrl
        self.tools = tools
        self.backupActor = BackupActor(config: config, configDir: configDir, dataDir: dataUrl)
        self.httpTokenFile = BackupService.configureToken(config: config, configDir: configDir)
    }

    static private func configureToken(config: BackupConfig, configDir: URL) -> URL {
        let tokenPath = config.tokenFileUrl(configDir: configDir)
        do {
            if FileManager.default.fileExists(atPath: tokenPath.path) {
                try FileManager.default.removeItem(at: tokenPath)
            }

            let tokenData = TokenCheckingMiddleware<ServiceContext>.generateToken()
            try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)
        } catch {
            BackupService.logger.error("Failed to write new token.")
        }

        return tokenPath
    }

    private func makeHttpService() -> some ApplicationProtocol {
        let router = Router(context: BasicRequestContext.self)
        self.configureRouter(router)

        let application = Application(
            router: router,
            configuration: .init(
                address: .hostname("0.0.0.0", port: 8080),
                serverName: "Bedrockifier"
            ),
            logger: BackupService.logger
        )

        return application
    }

    private func configureRouter(_ router: Router<ServiceContext>) {
        // Read-Only Unsecured Endpoints
        router.get("/live", use: handleHealthStatus)
        router.get("/health", use: handleHealthStatus)
        router.get("/status", use: handleServerStatus)

        router.group()
            .add(middleware: TokenCheckingMiddleware(tokenFile: httpTokenFile))
            .get("/start-backup", use: handleStartBackup)
            .get("/listen", use: handleNotImplemented) // NYI
    }

    @Sendable
    private func handleHealthStatus(
        to request: Request,
        context: ServiceContext
    ) async throws -> HTTPResponse.Status {
        let isHealthy = await backupActor.checkHealth()
        return isHealthy ? .ok : .serviceUnavailable
    }

    @Sendable
    private func handleServerStatus(
        to request: Request,
        context: ServiceContext
    ) async throws -> ServiceState {
        let lastResult = await backupActor.lastBackupResult()
        let response = ServiceState(lastBackup: lastResult)

        return response
    }

    @Sendable
    private func handleStartBackup(
        to request: Request,
        context: ServiceContext
    ) async throws -> HTTPResponse.Status {
        await backupActor.backupAllContainers(isDaily: true)
        return .ok
    }

    @Sendable
    private func handleNotImplemented(
        to request: Request,
        context: ServiceContext
    ) async throws -> HTTPResponse.Status {
        return .notImplemented
    }

    public func run() async throws {
        // Do startup validation
        try validateServerFolders()
        if await !backupActor.markHealthy(forceWrite: true) {
            throw ServiceError.unableToMarkHealthy
        }

        Task {
            BackupService.logger.info("Starting HTTP Service...")
            let httpService = makeHttpService()
            try await httpService.runService()
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

            if schedule.daily != nil {
                Task(priority: BackupService.backupPriority) {
                    try await runDailyBackups()
                }
            }

            if await backupActor.needsListeners() {
                await startListenerBackups()
                Task(priority: BackupService.backupPriority) {
                    await runListenerReconnectMonitor()
                }
            }

            if let minInterval = try schedule.parseMinInterval() {
                BackupService.logger.info("Backup Minimum Interval is \(minInterval) seconds.")
            }

            if schedule.runInitialBackup == true {
                BackupService.logger.info("Performing Initial Backup...")
                await self.backupActor.backupAllContainers(isDaily: true)
            }
        }

        try await runIntervalBackupsOrSleep()
    }

    private func connectContainers() async throws {
        let containers = try await ContainerConnection.loadContainers(from: config, tools: tools)

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

    private func runIntervalBackupsOrSleep() async throws {
        if let interval = try? getBackupInterval() {
            BackupService.logger.info("Backup Interval: \(interval) seconds")
            let timer = AsyncTimerSequence(interval: .seconds(interval), clock: .continuous)
            for await _ in timer {
                await self.backupActor.backupAllContainers(isDaily: false)
            }
        } else {
            repeat {
                try await Task.sleep(for: BackupService.defaultSleepInterval)
            } while !Task.isCancelled
        }
    }

    private func runDailyBackups() async throws {
        guard let dayTime = config.schedule?.daily else {
            BackupService.logger.error("Unable to Parse Daily Backup Time")
            throw ServiceError.noBackupInterval
        }

        repeat {
            guard let nextFiring = dayTime.calcNextDate(after: .now) else {
                BackupService.logger.error("Unable to calculate next daily backup date")
                throw ServiceError.noBackupInterval
            }

            try await Task.sleep(until: nextFiring)

            await self.backupActor.backupAllContainers(isDaily: true)
        } while true
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

    private func runListenerReconnectMonitor() async {
        let interval = getListenerReconnectInterval()
        BackupService.logger.info("Listener Reconnect Interval: \(interval) seconds")
        let timer = AsyncTimerSequence(interval: .seconds(interval), clock: .continuous)
        for await _ in timer {
            await self.backupActor.reconnectListenersIfNeeded()
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
            return try parse(interval: interval)
        }

        return nil
    }

    private func getStartupDelay() throws -> TimeInterval? {
        return try config.schedule?.parseStartupDelay()
    }

    private func getListenerReconnectInterval() -> TimeInterval {
        let configuredInterval = config.listenerReconnectInterval ?? environment.listenerReconnectInterval
        do {
            if let interval = configuredInterval {
                return max(5.0, try parse(interval: interval))
            }
        } catch {
            if let interval = configuredInterval {
                BackupService.logger.warning(
                    "Failed to parse listener reconnect interval '\(interval)'. Falling back to 60s."
                )
            }
        }

        return 60.0
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
