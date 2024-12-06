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
import Hummingbird

struct TokenCheckingMiddleware<Context>: RouterMiddleware {
    private let tokenFile: URL

    init(tokenFile: URL) {
        self.tokenFile = tokenFile
    }

    public static func generateToken() -> String {
        let token = UUID().uuid
        var tokenData = Data(count: 16)
        tokenData[0] = token.0
        tokenData[1] = token.1
        tokenData[2] = token.2
        tokenData[3] = token.3
        tokenData[4] = token.4
        tokenData[5] = token.5
        tokenData[6] = token.6
        tokenData[7] = token.7
        tokenData[8] = token.8
        tokenData[9] = token.9
        tokenData[10] = token.10
        tokenData[11] = token.11
        tokenData[12] = token.12
        tokenData[13] = token.13
        tokenData[14] = token.14
        tokenData[15] = token.15
        return tokenData.base64EncodedString()
    }

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        guard let currentToken = try? String(contentsOf: tokenFile) else {
            throw HTTPError(.internalServerError, message: "Cannot accept requests at this time.")
        }

        guard let token = request.headers[.authorization], token == "Bearer \(currentToken)" else {
            throw HTTPError(.badRequest, message: "Invalid authorization.")
        }

        return try await next(request, context)
    }


}
