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
import NIOSSH

public actor SSHHostKeyValidator {
    enum Result {
        case ok
        case notFound
        case changed
    }

    enum ValidatorError: Error {
        case dataCannotBeConverted
    }

    private let keysFile: URL

    public init(keysFile: URL) {
        self.keysFile = keysFile
    }

    func validate(hostIdent: String, publicKey: NIOSSHPublicKey) throws -> Result {
        let keys = loadKeys()
        guard let publicKeyStr = keys[hostIdent] else { return .notFound }

        let knownKey = try NIOSSHPublicKey(openSSHPublicKey: publicKeyStr)
        if knownKey != publicKey {
            return .changed
        }

        return .ok
    }

    func recordKey(hostIdent: String, publicKey: NIOSSHPublicKey) throws {
        var keys = loadKeys()

        keys[hostIdent] = String(openSSHPublicKey: publicKey)
        try writeKeys(keys)
    }

    private func loadKeys() -> [String:String] {
        do {
            let keyData = try Data(contentsOf: self.keysFile)
            guard let keyString = String(data: keyData, encoding: .utf8) else {
                return [:]
            }

            var result: [String:String] = [:]
            let lines = keyString.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
                guard parts.count == 2 else { continue }
                result[String(parts[0])] = String(parts[1])
            }

            return result
        } catch {
            return [:]
        }
    }

    private func writeKeys(_ keys: [String:String]) throws {
        var lines: [String] = []
        for (hostIdentifier, keyValue) in keys {
            lines.append("\(hostIdentifier) \(keyValue)")
        }

        let fileContentStr = lines.joined(separator: "\n")
        guard let fileContentData = fileContentStr.data(using: .utf8) else {
            throw ValidatorError.dataCannotBeConverted
        }

        try fileContentData.write(to: self.keysFile)
    }
}
