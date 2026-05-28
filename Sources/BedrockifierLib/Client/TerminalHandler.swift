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
import PTYKit

/// A ChannelDuplexHandler that is meant to be paired with a PseudoTerminal.
/// By putting it at the end of a chain of handlers, it can take raw UTF-8 buffers and push them through a PTY.
/// This means the handlers in front of it just need to convert between the line protocol and raw text buffers.
final class TerminalHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let convertNewlines: Bool
    private let terminal: PseudoTerminal
    private var terminalChannel: PseudoTerminal.Channel?

    init(terminal: PseudoTerminal, convertNewlines: Bool = true) {
        self.terminal = terminal
        self.convertNewlines = convertNewlines
    }

    deinit {
        guard let terminalChannel else { return }

        Task {
            do {
                try await terminalChannel.disconnect()
                Library.log.info("NIO Terminal disconnected from deinit.")
            } catch {
                Library.log.error(
                    "Failed to disconnect from Terminal during deinit. (\(error.localizedDescription))"
                )
            }
        }
    }

    func handlerAdded(context: ChannelHandlerContext) {
        Task {
            do {
                Library.log.trace("Connecting NIO Terminal.")
                let channel = try await terminal.connect()
                channel.fileHandle.readabilityHandler = { handle in
                    guard var string = String(data: handle.availableData, encoding: .utf8) else {
                        Library.log.error("Failed to read terminal data as UTF8 for NIO.")
                        return
                    }

                    if self.convertNewlines {
                        string = string.convertNewlinesForSSH()
                    }
                    Library.log.trace("Read data from NIO terminal: '\(string.debugDescription)'")
                    let buffer = ByteBuffer(string: string)
                    context.writeAndFlush(self.wrapOutboundOut(buffer)).whenFailure { error in
                        Library.log.error("Failed to write to Channel. (\(error.localizedDescription))")
                    }
                }

                self.terminalChannel = channel
                Library.log.info("NIO terminal connected.")
            } catch {
                Library.log.error("Failed to connect to terminal. (\(error.localizedDescription))")
            }
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        Task {
            self.terminalChannel?.fileHandle.readabilityHandler = nil
            do {
                try await self.terminalChannel?.disconnect()
                Library.log.info("NIO Terminal disconnected.")
            } catch {
                Library.log.error("Failed to disconnect from Terminal. (\(error.localizedDescription)")
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let bytes = unwrapInboundIn(data)
        let writableData = Data(buffer: bytes, byteTransferStrategy: .noCopy)
        Library.log.trace("Writing data to NIO terminal")
        if let terminalChannel = self.terminalChannel {
            do {
                try terminalChannel.fileHandle.write(contentsOf: writableData)
                Library.log.trace("Wrote data to NIO terminal")
            } catch {
                Library.log.error("Failed to write data to terminal fileHandle.")
            }
        }
    }
}
