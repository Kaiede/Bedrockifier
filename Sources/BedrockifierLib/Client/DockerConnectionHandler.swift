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

private struct ContainerInspectConfig: Decodable {
    let tty: Bool
    let openStdin: Bool

    enum CodingKeys: String, CodingKey {
        case tty = "Tty"
        case openStdin = "OpenStdin"
    }
}

private struct ContainerInspect: Decodable {
    let config: ContainerInspectConfig

    enum CodingKeys: String, CodingKey {
        case config = "Config"
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

    private func handleInspectHead(context: ChannelHandlerContext, part: HTTPClientResponsePart) {
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
    }

    private func handleInspectBody(context: ChannelHandlerContext, part: HTTPClientResponsePart) {
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
    }

    private func handleUpgradeHead(context: ChannelHandlerContext, part: HTTPClientResponsePart) {
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
    }

    private func handleUpgradeEnd(context: ChannelHandlerContext, part: HTTPClientResponsePart) {
        if case .end = part {
            beginUpgrade(context: context)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch state {
        case .awaitingInspectHead:
            handleInspectHead(context: context, part: part)

        case .readingInspectBody:
            handleInspectBody(context: context, part: part)

        case .awaitingUpgradeHead:
            handleUpgradeHead(context: context, part: part)

        case .awaitingUpgradeEnd:
            handleUpgradeEnd(context: context, part: part)

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
