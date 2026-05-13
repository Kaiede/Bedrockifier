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

import NIOCore
import NIOHTTP1
import NIOPosix
import PTYKit

enum DockerClientError: Error {
    case invalidResponse
    case upgradeFailed(String)
    case connectionClosed
    case inspectFailed(String)
    case stdinUnavailable(String)
}

private struct ContainerInspect: Decodable {
    struct Config: Decodable {
        let tty: Bool
        let openStdin: Bool

        enum CodingKeys: String, CodingKey {
            case tty = "Tty"
            case openStdin = "OpenStdin"
        }
    }

    let config: Config

    enum CodingKeys: String, CodingKey {
        case config = "Config"
    }
}

final class DockerClient {
    private let group: EventLoopGroup
    private let terminal: PseudoTerminal
    private let socketPath: String

    private var connectedChannel: Channel?
    private var attachedContainer: String?
    private var reconnectAttemptTask: Task<Void, Never>?
    private var isConnecting = false
    private var reconnectState = SSHReconnectState()

    private let onDisconnect: (() -> Void)?

    init(
        group: EventLoopGroup,
        terminal: PseudoTerminal,
        socketPath: String,
        onDisconnect: (() -> Void)? = nil
    ) {
        self.group = group
        self.terminal = terminal
        self.socketPath = socketPath
        self.onDisconnect = onDisconnect
    }

    var isConnected: Bool {
        return connectedChannel?.isActive == true
    }

    func connect(containerName: String) async throws {
        guard !isConnecting else {
            Library.log.debug("Skipping duplicate Docker connect request while a connect is already in progress.")
            return
        }

        self.isConnecting = true
        defer { self.isConnecting = false }

        self.attachedContainer = containerName
        Library.log.info("Connecting to Docker container '\(containerName)' via \(socketPath)")

        let terminal = self.terminal
        let connectPromise = group.next().makePromise(of: Void.self)

        let httpEncoder = HTTPRequestEncoder()
        let httpDecoder = ByteToMessageHandler(
            HTTPResponseDecoder(leftOverBytesStrategy: .forwardBytes)
        )

        let connectionHandler = DockerConnectionHandler(
            containerName: containerName,
            connectPromise: connectPromise,
            httpEncoder: httpEncoder,
            httpDecoder: httpDecoder
        ) { channel, isTTY in
            let terminalHandler = TerminalHandler(terminal: terminal, convertNewlines: !isTTY)
            
            if isTTY {
                return channel.pipeline.addHandler(terminalHandler)
            }
            return channel.pipeline.addHandlers([
                DockerStreamDemuxHandler(),
                terminalHandler
            ])
        }

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(.socketOption(.so_keepalive), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([httpEncoder, httpDecoder, connectionHandler])
            }

        Library.log.trace("Opening docker socket...")
        let channel = try await bootstrap.connect(unixDomainSocketPath: socketPath).get()
        do {
            try await connectPromise.futureResult.get()
        } catch {
            try? await channel.close()
            throw error
        }

        Library.log.trace("Creating channel.")
        self.connectedChannel = channel
        channel.closeFuture.whenComplete { [weak self, weak channel] _ in
            guard let self = self, let channel = channel else { return }

            let wasActiveChannel = self.connectedChannel === channel
            if wasActiveChannel {
                self.connectedChannel = nil
                self.startReconnectCycleIfNeeded()
            }
            Library.log.warning("Docker connection closed.")
        }

        Library.log.info("Attached to container '\(containerName)'.")
    }

    func close() async throws {
        Library.log.trace("Closing Docker connection.")
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

    private func startReconnectCycleIfNeeded() {
        guard reconnectState.shouldStartReconnectCycle(onDisconnectFromActiveChannel: true) else {
            return
        }

        guard reconnectAttemptTask == nil else {
            return
        }

        guard let container = attachedContainer else {
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
                Library.log.info("Detected Docker disconnect. Attempting immediate reconnect...")
                try await self.connect(containerName: container)
            } catch is CancellationError {
                Library.log.debug("Reconnect attempt cancelled.")
            } catch {
                Library.log.warning("Immediate reconnect attempt failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Drives the Docker attach lifecycle on top of NIOHTTP1:
///   1. GET `/containers/{name}/json` -> parse `Config.Tty` / `Config.OpenStdin`.
///   2. POST `/containers/{name}/attach` with `Upgrade: tcp` -> wait for 101.
///   3. Reconfigure the pipeline: install the post-upgrade handlers, then remove
///      the HTTP codec (forwarding any unread bytes as raw ByteBuffers) and self.
final class DockerConnectionHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private enum State {
        case awaitingInspectHead
        case readingInspectBody
        case awaitingUpgradeHead
        case awaitingUpgradeEnd
        case reconfiguring
        case streaming
        case failed
    }

    private let containerName: String
    private let connectPromise: EventLoopPromise<Void>
    private let httpEncoder: HTTPRequestEncoder
    private let httpDecoder: ByteToMessageHandler<HTTPResponseDecoder>
    private let installPostUpgradeHandlers: (Channel, Bool) -> EventLoopFuture<Void>

    private var state: State = .awaitingInspectHead
    private var inspectBody: ByteBuffer?
    private var isTTY = false

    init(
        containerName: String,
        connectPromise: EventLoopPromise<Void>,
        httpEncoder: HTTPRequestEncoder,
        httpDecoder: ByteToMessageHandler<HTTPResponseDecoder>,
        installPostUpgradeHandlers: @escaping (Channel, Bool) -> EventLoopFuture<Void>
    ) {
        self.containerName = containerName
        self.connectPromise = connectPromise
        self.httpEncoder = httpEncoder
        self.httpDecoder = httpDecoder
        self.installPostUpgradeHandlers = installPostUpgradeHandlers
    }

    func channelActive(context: ChannelHandlerContext) {
        sendInspectRequest(context: context)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch state {
        case .awaitingInspectHead:
            guard case .head(let head) = part else {
                fail(DockerClientError.invalidResponse, context: context)
                return
            }
            guard head.status == .ok else {
                Library.log.error("Docker inspect failed: \(head.status)")
                fail(DockerClientError.inspectFailed("\(head.status)"), context: context)
                return
            }
            state = .readingInspectBody

        case .readingInspectBody:
            switch part {
            case .body(var chunk):
                if inspectBody == nil {
                    inspectBody = chunk
                } else {
                    inspectBody?.writeBuffer(&chunk)
                }
            case .end:
                finishInspect(context: context)
            case .head:
                fail(DockerClientError.invalidResponse, context: context)
            }

        case .awaitingUpgradeHead:
            guard case .head(let head) = part else {
                // .body or .end before .head is malformed.
                fail(DockerClientError.invalidResponse, context: context)
                return
            }
            guard head.status == .switchingProtocols else {
                Library.log.error("Docker attach upgrade failed: \(head.status)")
                fail(DockerClientError.upgradeFailed("\(head.status)"), context: context)
                return
            }
            state = .awaitingUpgradeEnd

        case .awaitingUpgradeEnd:
            if case .end = part {
                beginUpgrade(context: context)
            }
            // Ignore any stray .body

        case .reconfiguring, .streaming, .failed:
            return
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        Library.log.error("Docker pipeline error: \(error.localizedDescription)")
        fail(error, context: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if state != .streaming, state != .failed {
            state = .failed
            connectPromise.fail(DockerClientError.connectionClosed)
        }
        context.fireChannelInactive()
    }

    private func sendInspectRequest(context: ChannelHandlerContext) {
        Library.log.trace("Sending docker inspect request.")
        var head = HTTPRequestHead(
            version: .http1_1,
            method: .GET,
            uri: "/containers/\(containerName)/json"
        )
        head.headers.add(name: "Host", value: "docker")
        head.headers.add(name: "Accept", value: "application/json")
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func sendUpgradeRequest(context: ChannelHandlerContext) {
        Library.log.trace("Sending docker attach upgrade.")
        var head = HTTPRequestHead(
            version: .http1_1,
            method: .POST,
            uri: "/containers/\(containerName)/attach?stream=1&stdin=1&stdout=1&stderr=1"
        )
        head.headers.add(name: "Host", value: "docker")
        head.headers.add(name: "Connection", value: "Upgrade")
        head.headers.add(name: "Upgrade", value: "tcp")
        head.headers.add(name: "Content-Length", value: "0")
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func finishInspect(context: ChannelHandlerContext) {
        let bodyBytes: [UInt8]
        if var body = inspectBody {
            bodyBytes = body.readBytes(length: body.readableBytes) ?? []
        } else {
            bodyBytes = []
        }
        inspectBody = nil

        let inspect: ContainerInspect
        do {
            inspect = try JSONDecoder().decode(ContainerInspect.self, from: Data(bodyBytes))
        } catch {
            Library.log.error("Failed to decode docker inspect response: \(error.localizedDescription)")
            fail(error, context: context)
            return
        }

        guard inspect.config.openStdin || inspect.config.tty else {
            Library.log.error("Container '\(containerName)' was not started with stdin open; cannot control this container.")
            fail(DockerClientError.stdinUnavailable(containerName), context: context)
            return
        }

        isTTY = inspect.config.tty
        Library.log.debug("Container '\(containerName)' inspect: TTY=\(isTTY), OpenStdin=true")

        state = .awaitingUpgradeHead
        sendUpgradeRequest(context: context)
    }

    private func beginUpgrade(context: ChannelHandlerContext) {
        Library.log.debug("Docker attach upgrade accepted.")
        state = .reconfiguring

        let pipeline = context.pipeline
        let channel = context.channel
        let encoder = self.httpEncoder
        let decoder = self.httpDecoder

        // Order matters: add the new handlers first so they're in place to receive
        // any leftover bytes when the decoder is removed. Remove ourselves before
        // the decoder so the forwarded raw bytes bypass us and reach the demux.
        installPostUpgradeHandlers(channel, isTTY)
            .flatMap { pipeline.removeHandler(encoder) }
            .flatMap { pipeline.removeHandler(self) }
            .flatMap { pipeline.removeHandler(decoder) }
            .whenComplete { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    Library.log.debug("Docker attach upgrade completed.")
                    self.state = .streaming
                    self.connectPromise.succeed(())
                case .failure(let error):
                    Library.log.error("Failed to reconfigure pipeline after upgrade: \(error.localizedDescription)")
                    self.state = .failed
                    self.connectPromise.fail(error)
                    context.close(promise: nil)
                }
            }
    }

    private func fail(_ error: Error, context: ChannelHandlerContext) {
        guard state != .failed, state != .streaming, state != .reconfiguring else { return }
        state = .failed
        connectPromise.fail(error)
        context.close(promise: nil)
    }
}

/// Strips Docker's 8-byte stdout/stderr framing from non-TTY attach streams,
/// forwarding only payload bytes downstream. stdin (outbound) is never framed,
/// so writes from later handlers pass through untouched.
final class DockerStreamDemuxHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    private static let headerSize = 8

    private var pending: ByteBuffer?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        if pending == nil {
            pending = incoming
        } else {
            pending?.writeBuffer(&incoming)
        }
        drain(context: context)
    }

    private func drain(context: ChannelHandlerContext) {
        guard var buffer = pending else { return }

        while buffer.readableBytes >= Self.headerSize {
            let lengthOffset = buffer.readerIndex + 4
            guard let length = buffer.getInteger(at: lengthOffset, endianness: .big, as: UInt32.self) else {
                break
            }
            let frameSize = Self.headerSize + Int(length)
            guard buffer.readableBytes >= frameSize else { break }

            buffer.moveReaderIndex(forwardBy: Self.headerSize)
            if length > 0, let payload = buffer.readSlice(length: Int(length)) {
                context.fireChannelRead(wrapInboundOut(payload))
            }
        }

        pending = buffer.readableBytes > 0 ? buffer : nil
    }
}
