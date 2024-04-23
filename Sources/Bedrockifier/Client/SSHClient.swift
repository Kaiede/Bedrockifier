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

    init(group: EventLoopGroup, terminal: PseudoTerminal, validator: SSHHostKeyValidator, password: ContainerPassword) {
        self.group = group
        self.terminal = terminal
        self.userAuthDelegate = SSHBasicAuthDelegate(password: password)
        self.serverAuthDelegate = SSHAcceptKnownHostKeysDelegate(validator: validator)
    }

    func connect(host: String, port: Int) async throws {
        Library.log.info("Connecting to \(host):\(port)")
        self.serverAuthDelegate.updateHost(host: host, port: port)
        let bootstrap = makeBootstrap()
        let channel = try await bootstrap.connect(host: host, port: port).get()

        self.connectedChannel = try await channel.pipeline.handler(type: NIOSSHHandler.self).flatMap { [self] handler in
            return makeChildHandler(eventLoop: channel.eventLoop, handler: handler)
        }.get()
    }

    var isConnected: Bool {
        return connectedChannel != nil
    }

    func close() async throws {
        Library.log.trace("Closing SSH connection.")
        self.serverAuthDelegate.disconnected()
        try await connectedChannel?.close()
        self.connectedChannel = nil
    }

    private func makeBootstrap() -> ClientBootstrap {
        return ClientBootstrap(group: group)
            .channelInitializer(self.initializeChannel)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
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
                case .ok:
                    Library.log.debug("Accepting host key, matches existing host key.")
                    validationCompletePromise.succeed()
                    return
                case .notFound:
                    Library.log.info("Existing host key not found. Accepting and recording.")
                    try await validator.recordKey(hostIdent: hostIdent, publicKey: hostKey)
                    validationCompletePromise.succeed()
                    return
                case .changed:
                    Library.log.error("Host key does not match existing key. If this is a mistake, ")
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
