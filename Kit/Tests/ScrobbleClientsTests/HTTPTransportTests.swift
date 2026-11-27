import Foundation
import Testing
@testable import ScrobbleClients

@Suite struct HTTPTransportTests {
    private func allows(_ from: String, _ to: String) -> Bool {
        RedirectPolicy.allows(from: URL(string: from)!, to: URL(string: to)!)
    }

    @Test func sameOriginRedirectIsAllowed() {
        #expect(allows("https://api.example.com/a", "https://api.example.com/b?x=1"))
        #expect(allows("https://API.example.com/a", "https://api.example.com/b"))
        #expect(allows("https://api.example.com:443/a", "https://api.example.com/b"))
    }

    @Test func sameHostHttpsUpgradeIsAllowed() {
        #expect(allows("http://api.example.com/a", "https://api.example.com/a"))
        #expect(allows("http://api.example.com:8080/a", "https://api.example.com:8080/a"))
        #expect(!allows("http://api.example.com/a", "https://api.example.com:8443/a"))
        #expect(!allows("http://api.example.com/a", "https://other.example.com/a"))
    }

    @Test func otherHostDowngradeOrPortIsRefused() {
        #expect(!allows("https://api.example.com/a", "https://evil.example.net/a"))
        #expect(!allows("https://api.example.com/a", "http://api.example.com/a"))
        #expect(!allows("https://api.example.com/a", "https://api.example.com:8443/a"))
        #expect(!allows("https://api.example.com/a", "file:///etc/hosts"))
    }

    @Test func responseLimitChecksDeclaredAndReceivedSize() throws {
        try ResponseLimit.check(expected: -1, received: 0)
        try ResponseLimit.check(expected: 1_048_576, received: 1_048_576)
        #expect(throws: URLError.self) { try ResponseLimit.check(expected: 1_048_577, received: 0) }
        #expect(throws: URLError.self) { try ResponseLimit.check(expected: -1, received: 1_048_577) }
    }
}


final class RedirectStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let response: HTTPURLResponse
        var body: String
        if url.host == "origin.test" {
            response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": "https://evil.test/steal"])!
            body = "redirecting"
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://evil.test/steal")!),
                                redirectResponse: response)
            // A refused redirect makes URLSession deliver the 3xx itself; the stub must then finish the body.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        body = "followed"
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite struct URLSessionTransportRedirectTests {
    @Test func crossHostRedirectIsNotFollowed() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectStubProtocol.self]
        let transport = URLSessionTransport(configuration: configuration)
        let (data, response) = try await transport.send(URLRequest(url: URL(string: "https://origin.test/api")!))
        #expect(response.statusCode == 302)
        #expect(String(decoding: data, as: UTF8.self) != "followed")
    }
}
