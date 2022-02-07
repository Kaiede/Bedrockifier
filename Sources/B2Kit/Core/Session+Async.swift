//
//  File.swift
//  
//
//  Created by Alex Hadden on 2/6/22.
//

#if compiler(>=5.5.2) && canImport(_Concurrency)
import AsyncHTTPClient
import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension B2Session {
    public func execute<Response>(_ request: B2Request<Response>) async throws -> Response {
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


    public func execute<Response>(_ request: B2Request<Response>) async throws -> Void {
        guard let taskRequest = try HTTPClient.Request(request: request, authorization: currentAuthorization) else {
            throw B2Error.invalidRequest
        }

        let response = await httpClient.execute(request: taskRequest, deadline: .distantFuture)
        //let result = try request.decode(response: response, data: data)
        //request.success?(self, result)
        //return result
    }

}

#endif
