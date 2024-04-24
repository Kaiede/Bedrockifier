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

import PTYKit

protocol ContainerTerminal {
    var terminal: PseudoTerminal { get }

    func pauseAutosave() async throws
    func resumeAutosave() async throws
}

private struct ErrorStrings {
    static let dockerConnectError = "Got permission denied while trying to connect to the Docker daemon"

    static let possibleErrors = [
        ErrorStrings.dockerConnectError: ContainerConnection.ContainerError.dockerConnectPermissionError
    ]
}

internal extension ContainerTerminal {
    func setWindowSize(columns: UInt16, rows: UInt16) throws {
        return try terminal.setWindowSize(columns: columns, rows: rows)
    }
}

private extension ContainerTerminal {
    func expect(_ expressions: [String], timeout: TimeInterval) async throws -> PseudoTerminal.ExpectResult {
        let allExpectations = expressions + ErrorStrings.possibleErrors.keys

        let result = await terminal.expect(allExpectations, timeout: timeout)
        switch result {
        case .noMatch:
            break
        case .match(let matchString):
            for (errorKey, errorType) in ErrorStrings.possibleErrors where matchString.contains(errorKey) {
                throw errorType
            }
        }

        return result
    }
}

struct BedrockTerminal: ContainerTerminal {
    internal let terminal: PseudoTerminal

    func resumeAutosave() async throws {
        // Release Save Hold
        try terminal.sendLine("save resume")
        let saveResumeStrings = [
            "Changes to the level are resumed", // 1.17 and earlier
            "Changes to the world are resumed", // 1.18 and later
            "A previous save has not been completed"
        ]
        if try await expect(saveResumeStrings, timeout: 60.0) == .noMatch {
            throw ContainerConnection.ContainerError.resumeFailed
        }
    }

    func pauseAutosave() async throws {
        // Start Save Hold
        try terminal.sendLine("save hold")
        if try await expect(["Saving", "The command is already running"], timeout: 10.0) == .noMatch {
            throw ContainerConnection.ContainerError.pauseFailed
        }

        // Wait for files to be ready
        var attemptLimit = 3
        while attemptLimit > 0 {
            try terminal.sendLine("save query")
            if try await expect(["Files are now ready to be copied"], timeout: 10.0) == .noMatch {
                attemptLimit -= 1
            } else {
                break
            }
        }

        if attemptLimit < 0 {
            throw ContainerConnection.ContainerError.saveNotCompleted
        }
    }
}

struct JavaTerminal: ContainerTerminal {
    internal let terminal: PseudoTerminal

    func pauseAutosave() async throws {
        // Need a longer timeout on the flush in case server is still starting up
        try terminal.sendLine("save-all flush")
        if try await expect(["Saved the game"], timeout: 30.0) == .noMatch {
            throw ContainerConnection.ContainerError.pauseFailed
        }

        try terminal.sendLine("save-off")
        if try await expect(["Automatic saving is now disabled"], timeout: 10.0) == .noMatch {
            throw ContainerConnection.ContainerError.pauseFailed
        }
    }

    func resumeAutosave() async throws {
        try terminal.sendLine("save-on")
        let saveResumeStrings = [
            "Automatic saving is now enabled",
            "Saving is already turned on"
        ]
        if try await expect(saveResumeStrings, timeout: 60.0) == .noMatch {
            throw ContainerConnection.ContainerError.resumeFailed
        }
    }
}
