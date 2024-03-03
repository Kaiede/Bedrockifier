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
import NIOPosix
import PTYKit

protocol ContainerChannel {
    var isConnected: Bool { get }

    func start() async throws
    func close() async throws
    mutating func reset() throws
}

struct ProcessChannel: ContainerChannel {
    private let terminal: PseudoTerminal
    private let processUrl: URL
    private let processArgs: [String]
    private var process: Process

    init(terminal: PseudoTerminal, processUrl: URL, processArgs: [String]) throws {
        self.terminal = terminal
        self.processUrl = processUrl
        self.processArgs = processArgs
        self.process = try Process(processUrl, arguments: processArgs, terminal: terminal)
    }

    var isConnected: Bool { process.isRunning }

    func close() {
        process.terminate()
    }

    func start() throws {
        try self.process.run()
    }

    mutating func reset() throws {
        self.process = try Process(processUrl, arguments: processArgs, terminal: terminal)
    }
}

struct SecureShellChannel: ContainerChannel {
    private let host: String
    private let port: Int
    private var client: SSHClient

    init(terminal: PseudoTerminal, host: String, port: Int, password: String) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.client = SSHClient(group: group, terminal: terminal, password: password)
        self.host = host
        self.port = port
    }

    var isConnected: Bool { client.isConnected }

    func start() async throws {
        try await client.connect(host: host, port: port)
    }

    func close() async throws {
        try await client.close()
    }

    func reset() {}
}
