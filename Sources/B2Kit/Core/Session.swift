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

public class B2Session {
    public static let shared: B2Session = B2Session()
    internal var urlSession: URLSession = URLSession.shared

    internal var currentAuthorization: B2Authorization? = nil

    @available(iOS 15, tvOS 15, watchOS 8, macOS 12, *)
    public func request<Response>(_ request: B2Request<Response>) async throws -> Response {
        guard let taskRequest = try URLRequest(request: request, authorization: currentAuthorization) else {
            throw B2Error.invalidRequest
        }
        let (data, response) = try await urlSession.data(for: taskRequest, delegate: nil)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw B2Error.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let error = try decodeError(data)
            throw error
        }

        let result = try request.decode(response: response, data: data)
        request.success?(self, result)
        return result
    }

    private func decodeError(_ data: Data) throws -> B2ServerError {
        let decoder = JSONDecoder()
        return try decoder.decode(B2ServerError.self, from: data)
    }
}
