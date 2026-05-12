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
import NIOPosix
import PTYKit

enum DockerClientError: Error {
    case invalidResponse
    case upgradeFailed(String)
    case connectionClosed
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
        Library.log.info("Connecting Docker attach for container '\(containerName)' via \(socketPath)")

        let terminal = self.terminal
        let upgradePromise = group.next().makePromise(of: Void.self)
        let upgradeHandler = DockerAttachUpgradeHandler(
            containerName: containerName,
            upgradePromise: upgradePromise
        ) { channel in
            channel.pipeline.addHandler(TerminalHandler(terminal: terminal))
        }

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(upgradeHandler)
            }

        let channel = try await bootstrap.connect(unixDomainSocketPath: socketPath).get()

        do {
            try await upgradePromise.futureResult.get()
        } catch {
            try? await channel.close()
            throw error
        }

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

/// Sends the Docker attach request, parses the HTTP/1.1 response headers,
/// validates the 101 upgrade, then swaps itself out for the supplied post-upgrade
/// handlers so the rest of the pipeline sees a raw byte stream to the container.
final class DockerAttachUpgradeHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let containerName: String
    private let upgradePromise: EventLoopPromise<Void>
    private let installPostUpgradeHandlers: (Channel) -> EventLoopFuture<Void>

    private var responseBuffer: ByteBuffer?
    private var upgradeComplete = false

    init(
        containerName: String,
        upgradePromise: EventLoopPromise<Void>,
        installPostUpgradeHandlers: @escaping (Channel) -> EventLoopFuture<Void>
    ) {
        self.containerName = containerName
        self.upgradePromise = upgradePromise
        self.installPostUpgradeHandlers = installPostUpgradeHandlers
    }

    func channelActive(context: ChannelHandlerContext) {
        let path = "/containers/\(containerName)/attach?stream=1&stdin=1&stdout=1&stderr=1"
        let request =
            "POST \(path) HTTP/1.1\r\n" +
            "Host: docker\r\n" +
            "Connection: Upgrade\r\n" +
            "Upgrade: tcp\r\n" +
            "Content-Length: 0\r\n" +
            "\r\n"

        var buffer = context.channel.allocator.buffer(capacity: request.utf8.count)
        buffer.writeString(request)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var inbound = unwrapInboundIn(data)

        if upgradeComplete {
            // Post-upgrade reads should already be flowing past us. Pass through defensively.
            context.fireChannelRead(wrapInboundOut(inbound))
            return
        }

        if responseBuffer == nil {
            responseBuffer = inbound
        } else {
            responseBuffer?.writeBuffer(&inbound)
        }

        guard var buffer = responseBuffer else { return }
        guard let headerEnd = indexOfCRLFCRLF(in: buffer.readableBytesView) else {
            // Wait for more data; keep accumulating.
            responseBuffer = buffer
            return
        }

        let headerLength = headerEnd + 4
        let headerBytes = buffer.readBytes(length: headerLength) ?? []
        let leftover = buffer.readableBytes > 0 ? buffer.readSlice(length: buffer.readableBytes) : nil
        responseBuffer = nil

        guard let headers = String(bytes: headerBytes, encoding: .utf8) else {
            upgradePromise.fail(DockerClientError.invalidResponse)
            context.close(promise: nil)
            return
        }

        let statusLine = headers.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).first.map(String.init) ?? ""
        let parts = statusLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2, parts[1] == "101" else {
            Library.log.error("Docker attach upgrade failed: '\(statusLine)'")
            upgradePromise.fail(DockerClientError.upgradeFailed(statusLine))
            context.close(promise: nil)
            return
        }

        Library.log.debug("Docker attach upgrade accepted.")
        upgradeComplete = true

        installPostUpgradeHandlers(context.channel).whenComplete { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                // Forward any bytes that arrived after the headers — they belong to the post-upgrade pipeline.
                if let leftover = leftover, leftover.readableBytes > 0 {
                    context.fireChannelRead(self.wrapInboundOut(leftover))
                }
                context.pipeline.removeHandler(context: context).whenComplete { _ in
                    self.upgradePromise.succeed(())
                }
            case .failure(let error):
                self.upgradePromise.fail(error)
                context.close(promise: nil)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if !upgradeComplete {
            upgradePromise.fail(error)
        }
        Library.log.error("Docker pipeline error: \(error.localizedDescription)")
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !upgradeComplete {
            upgradePromise.fail(DockerClientError.connectionClosed)
        }
        context.fireChannelInactive()
    }

    private func indexOfCRLFCRLF(in bytes: ByteBufferView) -> Int? {
        // \r\n\r\n
        let needle: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        guard bytes.count >= needle.count else { return nil }
        let start = bytes.startIndex
        for offset in 0...(bytes.count - needle.count) {
            let i0 = bytes.index(start, offsetBy: offset)
            if bytes[i0] == needle[0]
                && bytes[bytes.index(i0, offsetBy: 1)] == needle[1]
                && bytes[bytes.index(i0, offsetBy: 2)] == needle[2]
                && bytes[bytes.index(i0, offsetBy: 3)] == needle[3] {
                return offset
            }
        }
        return nil
    }
}
