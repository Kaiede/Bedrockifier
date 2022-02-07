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

import Cryptor
import Foundation

public extension B2Request {
    static func getUploadUrl(bucketId: String) -> B2Request<B2UploadUrl> {
        return B2Request<B2UploadUrl>(
            function: "b2_get_upload_url",
            method: .post,
            payload: [
                "bucketId": bucketId
            ]
        )
    }

    static func uploadFile(url: B2UploadUrl, file: String, data: Data) throws -> B2Request<B2UploadResult> {
        guard let encodedFileName = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw B2Error.invalidRequest
        }
        return B2Request<B2UploadResult>(
            function: "b2_upload_file",
            method: .post,
            headers: [
                "X-Bz-File-Name": encodedFileName,
                "Content-Type": "b2/x-auto",
                "Content-Length": "\(data.count)",
                "X-Bz-Content-Sha1": data.sha1String
            ],
            payload: data,
            apiUrl: url.uploadUrl,
            authorization: url.authorizationToken
        )
    }

    static func startLargeFile(bucketId: String, file: String) throws -> B2Request<B2UploadResult> {
        guard let encodedFileName = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw B2Error.invalidRequest
        }
        return B2Request<B2UploadResult>(
            function: "b2_start_large_file",
            method: .post,
            payload: [
                "bucketId": bucketId,
                "fileName": encodedFileName,
                "contentType": "b2/x-auto"
            ]
        )
    }

    static func getUploadPartUrl(fileId: String) -> B2Request<B2UploadUrl> {
        return B2Request<B2UploadUrl>(
            function: "b2_get_upload_part_url",
            method: .post,
            payload: [
                "fileId": fileId
            ]
        )
    }

    static func uploadPart(url: B2UploadUrl, partNumber: Int, data: Data) -> B2Request<B2UploadResult> {
        return B2Request<B2UploadResult>(
            function: "b2_upload_part",
            method: .post,
            headers: [
                "X-Bz-Part-Number": "\(partNumber)",
                "Content-Length": "\(data.count)",
                "X-Bz-Content-Sha1": data.sha1String
            ],
            payload: data,
            apiUrl: url.uploadUrl,
            authorization: url.authorizationToken
        )
    }

    static func finishLargeFile(fileId: String, sha1Array: [String]) -> B2Request<B2UploadResult> {
        return B2Request<B2UploadResult>(
            function: "b2_finish_large_file",
            method: .post,
            payload: [
                "fileId": fileId,
                "part1Sha1Array": sha1Array
            ]
        )
    }
}

@available(iOS 15, tvOS 15, watchOS 8, macOS 12, *)
public extension B2Session {
    func getUploadUrl(bucketId: String) async throws -> B2UploadUrl {
        return try await execute(.getUploadUrl(bucketId: bucketId))
    }

    func uploadFile(url: B2UploadUrl, file: String, data: Data) async throws -> B2UploadResult {
        return try await execute(.uploadFile(url: url, file: file, data: data))
    }

    func startLargeFile(bucketId: String, file: String) async throws -> B2UploadResult {
        return try await execute(.startLargeFile(bucketId: bucketId, file: file))
    }

    func getUploadPartUrl(fileId: String) async throws -> B2UploadUrl {
        return try await execute(.getUploadPartUrl(fileId: fileId))
    }

    func uploadPart(url: B2UploadUrl, partNumber: Int, data: Data) async throws -> B2UploadResult {
        return try await execute(.uploadPart(url: url, partNumber: partNumber, data: data))
    }

    func finishLargeFile(fileId: String, sha1Array: [String]) async throws -> B2UploadResult {
        return try await execute(.finishLargeFile(fileId: fileId, sha1Array: sha1Array))
    }

    func uploadFile(_ file: URL, bucketId: String, uploadPath: String) async throws {
        guard let authorization = currentAuthorization else {
            return
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let fileSize = attributes[.size] as? UInt64 else {
            throw B2Error.invalidFile
        }

        if fileSize > authorization.recommendedPartSize {
            _ = try await uploadFileAsParts(file, partSize: authorization.recommendedPartSize, bucketId: bucketId, uploadPath: uploadPath)
        } else {
            _ = try await uploadSingleFile(file, bucketId: bucketId, uploadPath: uploadPath)
        }
    }

    private func uploadSingleFile(_ file: URL, bucketId: String, uploadPath: String) async throws -> B2UploadResult {
        let data = try Data(contentsOf: file)

        let uploadUrl = try await getUploadUrl(bucketId: bucketId)
        let result = try await uploadFile(url: uploadUrl, file: uploadPath, data: data)
        return result
    }

    private func uploadFileAsParts(_ file: URL, partSize: Int, bucketId: String, uploadPath: String) async throws -> B2UploadResult {
        let fileHandle = try FileHandle(forReadingFrom: file)
        defer {
            try? fileHandle.close()
        }

        let largeFileUpload = try await startLargeFile(bucketId: bucketId, file: uploadPath)
        let uploadUrl = try await getUploadPartUrl(fileId: largeFileUpload.fileId)

        // Part numbers start with 1
        var partNumber = 1
        var sha1Array: [String] = []
        while let part = try fileHandle.read(upToCount: partSize) {
            let partResult = try await uploadPart(url: uploadUrl, partNumber: partNumber, data: part)
            sha1Array.append(partResult.contentSha1)
            partNumber += 1
        }

        let uploadResult = try await finishLargeFile(fileId: largeFileUpload.fileId, sha1Array: sha1Array)
        return uploadResult
    }
}

public struct B2UploadUrl: Codable {
    // TODO: There is also bucketId (Single) or fileId (Part)
    // However, they aren't needed to perform an upload
    var uploadUrl: URL
    var authorizationToken: String
}

public struct B2UploadResult: Codable {
    // TODO: Much of this is left out right now, but this is the required bit for uploads.
    var fileId: String
    var contentSha1: String
}
