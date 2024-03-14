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

final class TerminalHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer

    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let terminal: PseudoTerminal
    private var terminalChannel: PseudoTerminal.Channel?

    init(terminal: PseudoTerminal) {
        self.terminal = terminal
    }

    deinit {
        do {
            try terminalChannel?.disconnect()
            Library.log.info("SSH Terminal disconnected from deinit.")
        } catch {
            Library.log.error("Failed to disconnect from Terminal during deinit. (\(error.localizedDescription)")
        }
    }

    func handlerAdded(context: ChannelHandlerContext) {
        do {
            let channel = try terminal.connect()
            channel.fileHandle.readabilityHandler = { handle in
                let buffer = ByteBuffer(data: handle.availableData)
                Library.log.trace("read data from terminal \(String(buffer: buffer).withEscapedInvisibles())")
                context.write(self.wrapOutboundOut(buffer), promise: nil)
            }

            self.terminalChannel = channel
            Library.log.info("SSH Terminal fully connected.")
        } catch {
            Library.log.error("Failed to connect to terminal. (\(error.localizedDescription))")
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.terminalChannel?.fileHandle.readabilityHandler = nil
        do {
            try self.terminalChannel?.disconnect()
            Library.log.info("SSH Terminal disconnected.")
        } catch {
            Library.log.error("Failed to disconnect from Terminal. (\(error.localizedDescription)")
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let bytes = unwrapInboundIn(data)
        let writableData = Data(buffer: bytes, byteTransferStrategy: .noCopy)
        Library.log.trace("writing data to terminal")
        if let terminalChannel = self.terminalChannel {
            do {
                try terminalChannel.fileHandle.write(contentsOf: writableData)
                Library.log.trace("written data to terminal")
            } catch {
                Library.log.error("Failed to write data to terminal fileHandle.")
            }
        }
    }
}
