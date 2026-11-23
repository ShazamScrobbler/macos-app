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

