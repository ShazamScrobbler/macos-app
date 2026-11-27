import Foundation
@testable import ScrobbleClients

actor StubTransport: HTTPTransport {
    struct Reply: Sendable {
        var status = 200
        var body: String
        var headers: [String: String] = [:]
        var error: (any Error)?
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        let reply = replies.removeFirst()
        if let error = reply.error { throw error }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }

    func form(_ index: Int) -> [String: String] {
        FormEncoding.decode(requests[index].httpBody ?? Data())
    }

    /// Decoded JSON request body. Read-only after creation, so safe to hand across the actor boundary.
    struct JSONBody: @unchecked Sendable {
        let value: [String: Any]
        subscript(key: String) -> Any? { value[key] }
    }

    func json(_ index: Int) -> JSONBody {
        JSONBody(value: (try? JSONSerialization.jsonObject(with: requests[index].httpBody ?? Data())) as? [String: Any] ?? [:])
    }
}
