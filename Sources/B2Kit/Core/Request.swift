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

public struct B2Request<Response> where Response: Decodable {
    public enum HTTPMethod: String, RawRepresentable {
        case get = "GET"
        case post = "POST"
    }

    let httpMethod: HTTPMethod
    let function: String
    let authorization: String?
    let apiUrl: URL?
    var success: ((B2Session, Response) -> Void)?
    let headers: Dictionary<String, String>?
    private let payloadDictionary: Dictionary<String, Any>?
    private let payloadData: Data?

    init(function: String,
         method: HTTPMethod,
         headers: Dictionary<String, String>? = nil,
         payload: Data? = nil,
         apiUrl: URL? = nil,
         authorization: String? = nil) {
        self.function = function
        self.httpMethod = method
        self.headers = headers
        self.apiUrl = apiUrl
        self.authorization = authorization
        self.payloadData = payload
        self.payloadDictionary = nil
        self.success = nil
    }

    init(function: String,
         method: HTTPMethod,
         headers: Dictionary<String, String>? = nil,
         payload: Dictionary<String, Any>,
         apiUrl: URL? = nil,
         authorization: String? = nil) {
        self.function = function
        self.httpMethod = method
        self.apiUrl = apiUrl
        self.authorization = authorization
        self.headers = headers
        self.payloadData = nil
        self.payloadDictionary = payload
        self.success = nil
    }

    func httpBody() throws -> Data? {
        if let data = payloadData {
            return data
        }

        if let dictionary = payloadDictionary {
            return try JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted)
        }

        return nil
    }

    func baseUrl(using authorization: B2Authorization?) -> URL? {
        return apiUrl ?? authorization?.apiUrl ?? URL(string: "https://api.backblazeb2.com")
    }

    func decode(response: URLResponse, data: Data) throws -> Response {
        let decoder = JSONDecoder()
        return try decoder.decode(Response.self, from: data)
    }

    mutating func onSuccess(_ handler: @escaping (B2Session, Response) -> Void) {
        self.success = handler
    }
}

extension URLRequest {
    init?<Response>(request: B2Request<Response>, authorization: B2Authorization?) throws {
        guard let baseUrl = request.baseUrl(using: authorization) else {
            return nil
        }
        let finalUrl = baseUrl.appendingPathComponent("/b2api/v1/\(request.function)")

        self.init(url: finalUrl)
        self.httpMethod = request.httpMethod.rawValue
        self.httpBody = try request.httpBody()

        // Request is allowed to override the default for uploads or initial authentication
        if let authorization = request.authorization ?? authorization?.authorizationToken {
            self.addValue(authorization, forHTTPHeaderField: "Authorization")
        }
    }
}
