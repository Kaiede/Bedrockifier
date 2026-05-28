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

public struct ServerExtras: BackupItem {
    public var name: String
    public var location: URL

    public init(url: URL) throws {
        let fileName = url.lastPathComponent
        let expression = try NSRegularExpression(pattern: "(.+?)\\.extras\\.(.+?)\\.zip", options: .caseInsensitive)
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        guard let match = expression.firstMatch(in: fileName, options: [], range: range) else {
            throw ServerExtrasError.invalidArchive(url)
        }

        guard let nameRange = Range(match.range(at: 1), in: fileName) else {
            throw ServerExtrasError.invalidFilename
        }

        self.name = String(fileName[nameRange])
        self.location = url
    }
}

extension ServerExtras {
    enum ServerExtrasError: Error {
        case invalidArchive(URL)
        case invalidFilename
    }
}

extension ServerExtras.ServerExtrasError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidArchive(let url): return "Unable to access extras archive at '\(url.path)'"
        case .invalidFilename: return "Unable to get server name from archive file name"
        }
    }
}
