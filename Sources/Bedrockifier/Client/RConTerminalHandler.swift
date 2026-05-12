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
import PTYKit

final class RConTerminalHandler {
    private let terminal: PseudoTerminal
    private let client: RConClient

    private var terminalChannel: PseudoTerminal.Channel?
    private var processingTask: Task<Void, Never>?
    private var commandContinuation: AsyncStream<String>.Continuation?
    private var lineBuffer: String = ""

    init(terminal: PseudoTerminal, client: RConClient) {
        self.terminal = terminal
        self.client = client
    }

    deinit {
        commandContinuation?.finish()
        processingTask?.cancel()
        do {
            try terminalChannel?.disconnect()
            Library.log.info("RCON Terminal disconnected from deinit.")
        } catch {
            Library.log.error("Failed to disconnect from Terminal during deinit. (\(error.localizedDescription)")
        }
    }

    func start() throws {
        let channel = try terminal.connect()
        let (stream, continuation) = AsyncStream<String>.makeStream()

        channel.fileHandle.readabilityHandler = { [weak self] handle in
            self?.handleTerminalRead(handle.availableData)
        }

        self.terminalChannel = channel
        self.commandContinuation = continuation

        self.processingTask = Task { [weak self] in
            for await command in stream {
                await self?.runCommand(command)
            }
        }

        Library.log.info("RCON Terminal fully connected.")
    }

    func stop() {
        commandContinuation?.finish()
        commandContinuation = nil
        processingTask?.cancel()
        processingTask = nil

        terminalChannel?.fileHandle.readabilityHandler = nil
        do {
            try terminalChannel?.disconnect()
            Library.log.info("RCON Terminal disconnected.")
        } catch {
            Library.log.error("Failed to disconnect from Terminal. (\(error.localizedDescription)")
        }
        terminalChannel = nil
    }

    private func handleTerminalRead(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else {
            Library.log.error("Failed to read terminal data as UTF8 for RCON.")
            return
        }

        Library.log.trace("Read data from terminal: '\(string.withEscapedInvisibles())'")
        lineBuffer.append(string)

        // RCON sends discrete commands, so split on newlines and dispatch each whole line.
        // Anything left after the final newline stays buffered for the next read.
        while let newlineRange = lineBuffer.rangeOfCharacter(from: .newlines) {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer.removeSubrange(lineBuffer.startIndex..<newlineRange.upperBound)

            let command = line.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { continue }
            commandContinuation?.yield(command)
        }
    }

    private func runCommand(_ command: String) async {
        do {
            Library.log.trace("Sending RCON command: '\(command)'")
            let response = try await client.sendCommand(command)
            writeResponseToTerminal(response)
        } catch {
            Library.log.error("Failed to send RCON command '\(command)': \(error.localizedDescription)")
        }
    }

    private func writeResponseToTerminal(_ response: String) {
        guard let terminalChannel = terminalChannel else { return }

        // Match the line conventions a terminal consumer expects (CRLF), and always
        // terminate the response so the next read on the consumer side is line-aligned.
        let normalized = response.convertNewlinesForSSH()
        let payload = normalized.hasSuffix("\r\n") ? normalized : normalized + "\r\n"
        Library.log.trace("Writing RCON response to terminal: '\(payload.withEscapedInvisibles())'")

        do {
            try terminalChannel.fileHandle.write(contentsOf: Data(payload.utf8))
        } catch {
            Library.log.error("Failed to write RCON response to terminal fileHandle.")
        }
    }
}
