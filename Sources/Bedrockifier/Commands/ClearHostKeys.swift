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

import ArgumentParser
import ConsoleKitTerminal

extension Bedrockifier {
    struct ClearHostKeys: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear-host-keys",
            abstract: "Clears the authorized host keys file."
        )

        @Option(help: "Path to the host keys file")
        var hostKeysPath: String?

        @Option(name: .shortAndLong, help: "Folder to read config from")
        var configFolder: String?

        func run() async throws {
            let terminal = initializeTerminal()
            let environment = EnvironmentConfig()
            let hostKeysUri = Bedrockifier.getHostKeyFileUrl(
                environment: environment,
                hostKeysPath: hostKeysPath,
                configFolder: configFolder
            )

            guard FileManager.default.fileExists(atPath: hostKeysUri.path) else {
                terminal.output("Host keys file already empty: \(hostKeysUri.path)")
                return
            }

            do {
                try FileManager.default.removeItem(at: hostKeysUri)
                terminal.output("Cleared host keys file: \(hostKeysUri.path)")
            } catch {
                terminal.error("Failed to clear host keys file: \(error.localizedDescription)")
            }
        }
    }
}
