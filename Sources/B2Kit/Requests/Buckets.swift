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
    static func listBuckets(accountId: String, bucketName: String? = nil) -> B2Request<B2BucketList> {
        var payload = [
            "accountId": accountId
        ]

        if let bucketName = bucketName {
            payload["bucketName"] = bucketName
        }

        return B2Request<B2BucketList>(
            function: "b2_list_buckets",
            method: .get,
            payload: payload
        )
    }
}

@available(iOS 15, tvOS 15, watchOS 8, macOS 12, *)
public extension B2Session {
    func listBuckets(accountId: String, bucketName: String? = nil) async throws -> B2BucketList {
        return try await request(.listBuckets(accountId: accountId, bucketName: bucketName))
    }
}

public struct B2BucketList: Codable {
    public var buckets: [B2Bucket]
}

public struct B2Bucket: Codable {
    public var accountId: String
    public var bucketId: String
    public var bucketName: String
    public var bucketType: String

    // TODO: There are more items here, but not necessary for upload
}
