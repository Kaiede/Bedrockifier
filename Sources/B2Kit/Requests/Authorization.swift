/*
 B2Kit

 Copyright (c) 2022 Adam Thayer
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

public extension B2Request {
    static func authorize(keyId: String, applicationKey: String) -> B2Request<B2Authorization> {
        var request = B2Request<B2Authorization>(
            function: "b2_authorize_account",
            method: .get,
            authorization: "Basic \(keyId):\(applicationKey)"
        )
        request.onSuccess({ (session, result) in
            session.currentAuthorization = result
        })
        return request
    }
}

@available(iOS 15, tvOS 15, watchOS 8, macOS 12, *)
public extension B2Session {
    func authorize(keyId: String, applicationKey: String) async throws -> B2Authorization {
        return try await self.request(.authorize(keyId: keyId, applicationKey: applicationKey))
    }
}

public struct B2Authorization: Codable {
    var accountId: String
    var authorizationToken: String

    var apiUrl: URL
    var downloadUrl: URL
    var s3ApiUrl: URL

    var recommendedPartSize: Int
    var absoluteMinimumPartSize: Int

    var allowed: Allowed

    struct Allowed: Codable {
        var capabilities: [String]
        var bucketId: String?
        var bucketName: String?
        var namePrefix: String?
    }
}
