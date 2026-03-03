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

import NIOCore
import NIOPosix
import NIOSSH
import PTYKit

final class SSHClient {
    private let group: EventLoopGroup
    private let terminal: PseudoTerminal
    private let userAuthDelegate: NIOSSHClientUserAuthenticationDelegate
    private let serverAuthDelegate: SSHAcceptKnownHostKeysDelegate

    private var connectedChannel: Channel?
    private var reconnectEndpoint: (host: String, port: Int)?
    private var reconnectAttemptTask: Task<Void, Never>?
    private var isConnecting = false
    private var reconnectState = SSHReconnectState()

    private let onDisconnect: (() -> Void)?

    init(
        group: EventLoopGroup,
        terminal: PseudoTerminal,
        validator: SSHHostKeyValidator,
        password: ContainerPassword,
        onDisconnect: (() -> Void)? = nil
    ) {
        self.group = group
        self.terminal = terminal
        self.userAuthDelegate = SSHBasicAuthDelegate(password: password)
        self.serverAuthDelegate = SSHAcceptKnownHostKeysDelegate(validator: validator)
        self.onDisconnect = onDisconnect
    }

    func connect(host: String, port: Int) async throws {
        guard !isConnecting else {
            Library.log.debug("Skipping duplicate SSH connect request while a connect is already in progress.")
            return
        }

        self.isConnecting = true
        defer { self.isConnecting = false }

        self.reconnectEndpoint = (host: host, port: port)
        Library.log.info("Connecting to \(host):\(port)")
        self.serverAuthDelegate.updateHost(host: host, port: port)
        let bootstrap = makeBootstrap()
        let channel = try await bootstrap.connect(host: host, port: port).get()

        let childChannel = try await channel.pipeline.handler(type: NIOSSHHandler.self).flatMap { [self] handler in
            return makeChildHandler(eventLoop: channel.eventLoop, handler: handler)
        }.get()

        self.connectedChannel = childChannel
        childChannel.closeFuture.whenComplete { [weak self, weak childChannel] _ in
            guard let self = self, let childChannel = childChannel else { return }
            let wasActiveChannel = self.connectedChannel === childChannel
            if wasActiveChannel {
                self.connectedChannel = nil
                self.startReconnectCycleIfNeeded()
            }
            Library.log.warning("SSH connection closed.")
        }
    }

    var isConnected: Bool {
        return connectedChannel?.isActive == true
    }

    func close() async throws {
        Library.log.trace("Closing SSH connection.")
        self.serverAuthDelegate.disconnected()
        self.reconnectState.beginExplicitClose()
        defer {
            self.reconnectState.endExplicitClose()
            self.connectedChannel = nil
            self.reconnectAttemptTask = nil
        }

        self.reconnectAttemptTask?.cancel()
        self.reconnectState.reconnectCycleCompleted()
        try await connectedChannel?.close()
    }

    private func makeBootstrap() -> ClientBootstrap {
        return ClientBootstrap(group: group)
            .channelInitializer(self.initializeChannel)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
    }

    private func initializeChannel(channel: Channel) -> EventLoopFuture<Void> {
        channel.pipeline.addHandlers([
            NIOSSHHandler(
                role: .client(.init(
                    userAuthDelegate: self.userAuthDelegate,
                    serverAuthDelegate: self.serverAuthDelegate
                )),
                allocator: channel.allocator,
                inboundChildChannelInitializer: nil),
            SSHErrorHandler()
        ])
    }

    private func makeChildHandler(eventLoop: EventLoop, handler: NIOSSHHandler) -> EventLoopFuture<Channel> {
        let promise = eventLoop.makePromise(of: Channel.self)
        handler.createChannel(promise) { child, channelType in
            guard channelType == .session else {
                return eventLoop.makeFailedFuture(SSHClientError.unsupportedChannelType)
            }

            return child.pipeline.addHandlers([
                SSHPipeHandler(),
                TerminalHandler(terminal: self.terminal),
                SSHErrorHandler()
            ])
        }

        return promise.futureResult
    }

    private func startReconnectCycleIfNeeded() {
        guard reconnectState.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true) else {
            return
        }

        guard reconnectAttemptTask == nil else {
            return
        }

        guard let endpoint = reconnectEndpoint else {
            reconnectState.reconnectCycleCompleted()
            return
        }

        reconnectAttemptTask = Task { [weak self] in
            guard let self = self else { return }
            defer {
                self.reconnectAttemptTask = nil
                self.reconnectState.reconnectCycleCompleted()
            }

            self.onDisconnect?()

            do {
                Library.log.info("Detected SSH disconnect. Attempting immediate reconnect...")
                try await self.connect(host: endpoint.host, port: endpoint.port)
            } catch is CancellationError {
                Library.log.debug("Reconnect attempt cancelled.")
            } catch {
                Library.log.warning("Immediate reconnect attempt failed: \(error.localizedDescription)")
            }
        }
    }
}

struct SSHReconnectState {
    private var reconnectCycleActive = false
    private var explicitCloseInProgress = false

    mutating func beginExplicitClose() {
        explicitCloseInProgress = true
        reconnectCycleActive = false
    }

    mutating func endExplicitClose() {
        explicitCloseInProgress = false
    }

    mutating func shouldStartReconnectCycle(onDisconnectFromActiveChannel isActiveChannel: Bool) -> Bool {
        guard isActiveChannel else { return false }
        guard !explicitCloseInProgress else { return false }
        guard !reconnectCycleActive else { return false }

        reconnectCycleActive = true
        return true
    }

    mutating func reconnectCycleCompleted() {
        reconnectCycleActive = false
    }
}

final class SSHAcceptKnownHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let validator: SSHHostKeyValidator
    private var currentHostIdentifier: String?

    enum HostKeyError: Error {
        case unknownHost
        case mismatchedKey
    }

    init(validator: SSHHostKeyValidator) {
        self.validator = validator
    }

    func updateHost(host: String, port: Int) {
        self.currentHostIdentifier = identifierString(host: host, port: port)
    }

    func disconnected() {
        self.currentHostIdentifier = nil
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        Task {
            guard let hostIdent = self.currentHostIdentifier else {
                Library.log.error("Cannot validate host key, host hasn't been identified.")
                validationCompletePromise.fail(HostKeyError.unknownHost)
                return
            }

            do {
                let result = try await validator.validate(hostIdent: hostIdent, publicKey: hostKey)
                switch result {
                case .keyOk:
                    Library.log.debug("Accepting host key, matches existing host key.")
                    validationCompletePromise.succeed()
                    return
                case .notFound:
                    Library.log.info("Existing host key not found. Accepting and recording.")
                    try await validator.recordKey(hostIdent: hostIdent, publicKey: hostKey)
                    validationCompletePromise.succeed()
                    return
                case .changed:
                    // swiftlint:disable:next line_length
                    Library.log.error("Host key does not match existing key. This could mean that you changed your server configuration recently, or the backup service contacted a different host than expected. See the wiki's Toubleshooting page for more.")
                    validationCompletePromise.fail(HostKeyError.mismatchedKey)
                }
            } catch {
                Library.log.error("Host key validation failed due to thrown error.")
                validationCompletePromise.fail(error)
            }
        }
    }

    private func identifierString(host: String, port: Int) -> String {
        "\(host):\(port)"
    }
}

final class SSHBasicAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username = "bedrockifier"
    private let password: ContainerPassword

    init(password: ContainerPassword) {
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSH.NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: NIOCore.EventLoopPromise<NIOSSH.NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.password) else {
            Library.log.error("SSH authentication failure. Password not supported by server.")
            nextChallengePromise.fail(SSHClientError.passwordAuthenticationNotSupported)
            return
        }

        do {
            let passwordString = try password.readPassword()

            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: self.username,
                    serviceName: "",
                    offer: .password(.init(password: passwordString)))
            )
        } catch ContainerPassword.ReadPasswordError.noPasswordProvided {
            Library.log.error("SSH authentication failure. No password was configured.")
            nextChallengePromise.fail(ContainerPassword.ReadPasswordError.noPasswordProvided)
        } catch ContainerPassword.ReadPasswordError.failedToReadFile {
            Library.log.error("SSH authentication failure. Failed to read password file.")
            nextChallengePromise.fail(ContainerPassword.ReadPasswordError.failedToReadFile)
        } catch {
            Library.log.error("SSH authentication failure. Unknown error.")
            nextChallengePromise.fail(error)
        }
    }
}

enum SSHClientError: Error {
    case passwordAuthenticationNotSupported
    case unsupportedChannelType
}
