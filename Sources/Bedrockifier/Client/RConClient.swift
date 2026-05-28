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

public enum RConError: Error {
    case notConnected
    case alreadyConnected
    case authenticationFailed
    case invalidFrameSize(Int)
    case frameTooLarge(Int)
    case unexpectedResponse
    case connectionClosed
}

final class RequestIDProvider {
    private var nextRequestID: Int32 = 1

    internal func nextID() -> Int32 {
        // Avoid -1 which is reserved by the protocol to indicate auth failure.
        var next = nextRequestID
        if next == -1 || next == 0 {
            next = 1
        }
        nextRequestID = next &+ 1
        return next
    }
}

final class RConClient {
    // Maximum allowed body size on an inbound packet. The Source RCON spec caps
    // responses at 4096 bytes; we allow a little extra slack for non-conforming servers.
    private static let maxBodyBytes = 4_110

    private let group: EventLoopGroup
    private let terminal: PseudoTerminal

    private var channel: Channel?
    private var handler: RConClientHandler?
    private let idProvider: RequestIDProvider

    public init(group: EventLoopGroup, terminal: PseudoTerminal) {
        self.group = group
        self.terminal = terminal
        self.idProvider = .init()
    }

    public var isConnected: Bool {
        channel?.isActive == true
    }

    public func connect(host: String, port: Int) async throws {
        guard channel == nil else {
            throw RConError.alreadyConnected
        }

        Library.log.info("Connecting RCON to \(host):\(port)")

        let handler = RConClientHandler()
        let maxBody = Self.maxBodyBytes
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(RConFrameDecoder(maxBodyBytes: maxBody)),
                    MessageToByteHandler(RConFrameEncoder()),
                    handler
                ])
            }

        let channel = try await bootstrap.connect(host: host, port: port).get()
        self.channel = channel
        self.handler = handler

        channel.closeFuture.whenComplete { _ in
            Library.log.debug("RCON connection closed.")
        }
    }

    public func authenticate(password: ContainerPassword) async throws {
        try await authenticate(password: password.readPassword())
    }

    public func authenticate(password: String) async throws {
        Library.log.trace("Authenticating RCON.")

        guard let channel = channel, let handler = handler else {
            throw RConError.notConnected
        }

        let requestID = idProvider.nextID()
        let response = try await sendFrame(
            RConFrame(id: requestID, type: RConFrame.typeAuth, body: password),
            isAuth: true
        )
        // Source RCON spec: failed auth responds with id == -1.
        if response.id == -1 {
            throw RConError.authenticationFailed
        }
        guard response.id == requestID else {
            throw RConError.unexpectedResponse
        }

        Library.log.trace("Authentication complete.")
        // Successful authenticate means we can convert into streaming mode
        try await channel.pipeline.removeHandler(handler)
        try await channel.pipeline.addHandlers([
            StreamHandler(idProvider: self.idProvider),
            TerminalHandler(terminal: self.terminal)
        ], position: .last)
    }

    public func close() async throws {
        guard let channel = channel else { return }
        self.channel = nil
        self.handler = nil
        try await channel.close()
    }

    private func sendFrame(_ frame: RConFrame, isAuth: Bool) async throws -> RConFrame {
        guard let channel = channel, let handler = handler else {
            throw RConError.notConnected
        }

        let future: EventLoopFuture<RConFrame> = channel.eventLoop.flatSubmit {
            handler.send(frame: frame, isAuth: isAuth, on: channel)
        }
        return try await future.get()
    }
}

struct RConFrame {
    static let typeResponseValue: Int32 = 0
    static let typeAuthResponse: Int32 = 2
    static let typeExecCommand: Int32 = 2
    static let typeAuth: Int32 = 3

    var id: Int32
    var type: Int32
    var body: String
}

extension RConFrame: CustomDebugStringConvertible {
    var debugDescription: String {
        "RConFrame(id: \(id), type: \(type), body: \(body.debugDescription))"
    }
}

struct RConFrameDecoder: ByteToMessageDecoder {
    typealias InboundOut = RConFrame

    let maxBodyBytes: Int

    mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        // Peek the size header without consuming it until we have the whole frame.
        guard let size = buffer.getInteger(at: buffer.readerIndex, endianness: .little, as: Int32.self) else {
            return .needMoreData
        }

        let frameSize = Int(size)
        // 10 = id(4) + type(4) + body null(1) + empty-string null(1)
        guard frameSize >= 10 else {
            throw RConError.invalidFrameSize(frameSize)
        }
        guard
            frameSize <= maxBodyBytes + 10 else {
            throw RConError.frameTooLarge(frameSize)
        }

        let totalBytes = 4 + frameSize
        guard buffer.readableBytes >= totalBytes else {
            return .needMoreData
        }

        buffer.moveReaderIndex(forwardBy: 4)
        let id = buffer.readInteger(endianness: .little, as: Int32.self) ?? 0
        let type = buffer.readInteger(endianness: .little, as: Int32.self) ?? 0

        // Read the remaining payload (body bytes + 2 null terminators) and trim trailing nulls.
        // Some servers (notably older Minecraft Java) are loose with the trailing empty string,
        // so trimming is more forgiving than reading a strict body length.
        let payloadLength = frameSize - 8
        var payload = buffer.readBytes(length: payloadLength) ?? []
        while payload.last == 0 {
            payload.removeLast()
        }
        let body = String(bytes: payload, encoding: .utf8) ?? ""

        context.fireChannelRead(wrapInboundOut(RConFrame(id: id, type: type, body: body)))
        return .continue
    }
}

struct RConFrameEncoder: MessageToByteEncoder {
    typealias OutboundIn = RConFrame

    func encode(data: RConFrame, out: inout ByteBuffer) throws {

        let bodyBytes = Array(data.body.utf8)
        let size = Int32(10 + bodyBytes.count)
        out.writeInteger(size, endianness: .little)
        out.writeInteger(data.id, endianness: .little)
        out.writeInteger(data.type, endianness: .little)
        out.writeBytes(bodyBytes)
        out.writeInteger(UInt8(0))
        out.writeInteger(UInt8(0))
    }
}

final class RConClientHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = RConFrame
    typealias InboundOut = RConFrame

    private var pending: [Int32: EventLoopPromise<RConFrame>] = [:]
    private var authPromise: EventLoopPromise<RConFrame>?

    func send(frame: RConFrame, isAuth: Bool, on channel: Channel) -> EventLoopFuture<RConFrame> {
        channel.eventLoop.preconditionInEventLoop()

        let promise = channel.eventLoop.makePromise(of: RConFrame.self)
        if isAuth {
            // Remove previous auth attempt if one exists.
            authPromise?.fail(RConError.unexpectedResponse)
            self.authPromise = promise
        } else {
            pending[frame.id]?.fail(RConError.unexpectedResponse)
            pending[frame.id] = promise
        }

        Library.log.trace("Sending RCON password.")
        channel.writeAndFlush(frame).whenFailure { [weak self] error in
            Library.log.error("RCON authentication write failed: \(error)")
            guard let self = self else { return }
            if isAuth {
                self.authPromise = nil
            } else {
                self.pending.removeValue(forKey: frame.id)
            }
            promise.fail(error)
        }
        return promise.futureResult
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        // During an auth handshake the server sends an empty SERVERDATA_RESPONSE_VALUE
        // immediately before the SERVERDATA_AUTH_RESPONSE — drop it.
        if let promise = authPromise, frame.type == RConFrame.typeAuthResponse {
            Library.log.trace("RCON received auth response.")
            authPromise = nil
            promise.succeed(frame)
            return
        }
        if authPromise != nil, frame.type == RConFrame.typeResponseValue {
            Library.log.trace("RCON received response during authentication.")
            return
        }

        if let promise = pending.removeValue(forKey: frame.id) {
            promise.succeed(frame)
        } else {
            Library.log.debug("RCON received unsolicited frame id=\(frame.id) type=\(frame.type)")
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        failAll(with: RConError.connectionClosed)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        Library.log.warning("RCON channel error: \(error.localizedDescription)")
        failAll(with: error)
        context.close(promise: nil)
    }

    private func failAll(with error: Error) {
        for (_, promise) in pending {
            promise.fail(error)
        }
        pending.removeAll()
        authPromise?.fail(error)
        authPromise = nil
    }
}

/// Handles conversion between the TerminalHandler, and RCon frames
private final class StreamHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = RConFrame
    typealias InboundOut = ByteBuffer

    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = RConFrame

    private let idProvider: RequestIDProvider

    init(idProvider: RequestIDProvider) {
        self.idProvider = idProvider
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard frame.type == RConFrame.typeResponseValue else {
            Library.log.error("Unexpected RCON frame type encountered after authentication: \(frame.type)")
            return
        }

        let byteBuffer = ByteBuffer(string: frame.body)
        context.fireChannelRead(wrapInboundOut(byteBuffer))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var byteBuffer = unwrapOutboundIn(data)
        guard var body = byteBuffer.readString(length: byteBuffer.readableBytes) else {
            return
        }

        body = body.trimmingCharacters(in: .newlines)
        let id = idProvider.nextID()
        let frame = RConFrame(id: id, type: RConFrame.typeExecCommand, body: body)
        context.write(self.wrapOutboundOut(frame), promise: promise)
    }
}
