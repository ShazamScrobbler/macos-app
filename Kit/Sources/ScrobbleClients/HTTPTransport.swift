import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Decides whether a redirect may be followed: only to the same scheme, host and port.
enum RedirectPolicy {
    static func allows(from: URL, to: URL) -> Bool {
        func origin(_ url: URL) -> (String, String, Int)? {
            guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
            let port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
            return (scheme, host, port)
        }
        guard let a = origin(from), let b = origin(to) else { return false }
        return a == b
    }
}

/// Response size cap shared by the transport and its tests.
enum ResponseLimit {
    static let maxBytes = 1_048_576

    static func check(expected: Int64, received: Int) throws {
        if expected > Int64(maxBytes) || received > maxBytes { throw URLError(.dataLengthExceedsMaximum) }
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        if let from = task.originalRequest?.url, let to = request.url, RedirectPolicy.allows(from: from, to: to) {
            completionHandler(request)
        } else {
            completionHandler(nil)   // the 3xx response is returned to the caller and treated as an error status
        }
    }
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "ShazamScrobbler/2 (macOS)"]
        session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }

    /// Streams the body with `bytes(for:)` so an oversized response stops early instead of being buffered whole.
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        try ResponseLimit.check(expected: http.expectedContentLength, received: 0)
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            try ResponseLimit.check(expected: -1, received: data.count)
        }
        return (data, http)
    }
}

public enum FormEncoding {
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    public static func encode(_ params: [String: String]) -> Data {
        Data(params.sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&").utf8)
    }

    public static func decode(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        for pair in String(decoding: data, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let name = parts.first?.removingPercentEncoding else { continue }
            result[name] = parts.count > 1 ? parts[1].removingPercentEncoding ?? "" : ""
        }
        return result
    }

    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
