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

public struct ToolConfig {
    let dockerPath: String
    let rconPath: String
    let sshPath: String
    let sshpassPath: String

    public init(dockerPath: String, rconPath: String, sshPath: String, sshpassPath: String) {
        self.dockerPath = dockerPath
        self.rconPath = rconPath
        self.sshPath = sshPath
        self.sshpassPath = sshpassPath
    }
}

public enum ContainerConnectionConfigKind {
    case docker
    case rcon
    case ssh
}

public protocol ContainerConnectionConfig {
    var processPath: String { get }
    var kind: ContainerConnectionConfigKind { get }
    var newline: TerminalNewline { get }
    var password: String { get }
    func makeArguments() throws -> [String]
}

extension ContainerConnectionConfig {
    var processUrl: URL { URL(fileURLWithPath: processPath) }
}

public struct DockerConnectionConfig: ContainerConnectionConfig {
    let dockerPath: String
    let containerName: String
    public let password: String = ""

    init(dockerPath: String, config: BackupConfig.ContainerConfig) {
        self.dockerPath = dockerPath
        self.containerName = config.name
    }

    init(dockerPath: String, containerName: String) {
        self.dockerPath = dockerPath
        self.containerName = containerName
    }

    public var kind: ContainerConnectionConfigKind { .docker }
    public var newline: TerminalNewline { .default }
    public var processPath: String { dockerPath }

    public func makeArguments() -> [String] {
        return [
            "attach",
            "--sig-proxy=false",
            containerName
        ]
    }
}

public struct RCONConnectionConfig: ContainerConnectionConfig {
    let rconPath: String
    let address: String
    public let password: String

    init?(rconPath: String, config: BackupConfig.ContainerConfig) {
        guard let rconAddr = config.rcon else { return nil }
        guard let rconPassword = config.readPassword() else {
            Library.log.error("Container is configured for RCON, but was unable to get a password to use. \(config.name)")
            return nil
        }

        self.rconPath = rconPath
        self.address = rconAddr
        self.password = rconPassword
    }

    public var kind: ContainerConnectionConfigKind { .rcon }
    public var newline: TerminalNewline { .ssh }
    public var processPath: String { rconPath }

    public func makeArguments() throws -> [String] {
        // TODO: Do some checking here...
        let parts = address.split(whereSeparator: { $0 == ":" })
        guard parts.count == 2 else {
            throw ParseError.invalidHostname(address)
        }

        return [
            "--host",
            "\(parts[0])",
            "--port",
            "\(parts[1])",
            "--password",
            "\(password)"
        ]
    }
}

public struct SSHConnectionConfig: ContainerConnectionConfig {
    let sshpassPath: String
    let sshPath: String
    let address: String
    public let password: String

    init?(sshpassPath: String, sshPath: String, config: BackupConfig.ContainerConfig) {
        guard let sshAddr = config.ssh else { return nil }
        guard let sshPassword = config.readPassword() else {
            Library.log.error("Container is configured for SSH, but was unable to get a password to use. \(config.name)")
            return nil
        }

        self.sshpassPath = sshpassPath
        self.sshPath = sshPath
        self.address = sshAddr
        self.password = sshPassword
    }

    public var kind: ContainerConnectionConfigKind { .ssh }
    public var newline: TerminalNewline { .ssh }
    public var processPath: String { sshpassPath }

    public func makeArguments() throws -> [String] {
        // TODO: Do some checking here...
        let parts = address.split(whereSeparator: { $0 == ":" })
        guard parts.count == 2 else {
            throw ParseError.invalidHostname(address)
        }

        return [
            String(parts[0]),
            String(parts[1])
        ]
    }
}
