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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import ArgumentParser
import ConsoleKitTerminal

extension Bedrockifier {
    struct Healthcheck: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "healthcheck",
            abstract: "Pings the running service's health endpoint."
        )

        @Option(help: "Host to ping (default = localhost)")
        var host: String = "localhost"

        @Option(help: "Port to ping (default = 8080)")
        var port: Int = 8080

        @Option(help: "Path to ping (default = /health)")
        var path: String = "/health"

        @Option(help: "Request timeout in seconds (default = 5)")
        var timeout: Double = 5

        func run() async throws {
            let terminal = initializeTerminal()

            var components = URLComponents()
            components.scheme = "http"
            components.host = host
            components.port = port
            components.path = path.hasPrefix("/") ? path : "/\(path)"

            guard let url = components.url else {
                terminal.error("Invalid health check URL.")
                throw ExitCode.failure
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout

            let response: URLResponse
            do {
                (_, response) = try await URLSession.shared.data(for: request)
            } catch {
                terminal.error("Health check failed reaching \(url.absoluteString): \(error.localizedDescription)")
                throw ExitCode.failure
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                terminal.error("Health check received non-HTTP response from \(url.absoluteString).")
                throw ExitCode.failure
            }

            let status = httpResponse.statusCode
            if (200..<300).contains(status) {
                terminal.output("Health check OK (HTTP \(status)).".consoleText(.info))
                return
            }

            terminal.error("Health check failed (HTTP \(status)).")
            throw ExitCode.failure
        }
    }
}
