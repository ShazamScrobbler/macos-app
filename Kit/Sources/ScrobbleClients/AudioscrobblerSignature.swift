import CryptoKit
import Foundation
import ScrobbleCore

public enum AudioscrobblerSignature {
    public static func sign(_ params: [String: String], secret: String) -> String {
        let base = params
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined() + secret
        return Insecure.MD5.hash(data: Data(base.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Shared request/response handling for every Audioscrobbler 2.0 call.
struct AudioscrobblerAPI: Sendable {
    let apiURL: URL
    let apiKey: String
    let apiSecret: String
    let transport: any HTTPTransport

    /// Returns the decoded JSON object or throws `ScrobbleError` (or `AudioscrobblerCallError` for auth codes).
    func call(method: String, params: [String: String], sessionKey: String? = nil,
              signed: Bool = true, get: Bool = false) async throws -> [String: Any] {
        var all = params
        all["method"] = method
        all["api_key"] = apiKey
        if let sessionKey { all["sk"] = sessionKey }
        if signed { all["api_sig"] = AudioscrobblerSignature.sign(all, secret: apiSecret) }
        all["format"] = "json"

        var request: URLRequest
        if get {
            var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
            components.queryItems = all.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
        } else {
            request = URLRequest(url: apiURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = FormEncoding.encode(all)
        }

        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) }
        catch { throw ScrobbleError.transient(error.localizedDescription) }

        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let object, let code = Self.int(object["error"]) {
            throw AudioscrobblerCallError(code: code, message: object["message"] as? String ?? "Error \(code)")
        }
        switch response.statusCode {
        case 200..<300:
            guard let object else { throw ScrobbleError.transient("Unreadable response from \(apiURL.host ?? "server")") }
            return object
        case 429: throw ScrobbleError.rateLimited(retryAfter: nil)
        default: throw ScrobbleError.transient("HTTP \(response.statusCode)")
        }
    }

    static func mapError(code: Int, message: String) -> ScrobbleError {
        switch code {
        case 9: .signedOut
        case 10, 13, 26: .keyUnusable(code: code)
        case 11, 16: .transient(message)
        case 29: .rateLimited(retryAfter: nil)
        default: .permanent(message)
        }
    }

    /// Last.fm sends numbers as either JSON numbers or strings.
    static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let s = value as? String { return Int(s) }
        return nil
    }

    /// Last.fm returns a single object instead of a one-element array.
    static func array(_ value: Any?) -> [[String: Any]] {
        if let array = value as? [[String: Any]] { return array }
        if let object = value as? [String: Any] { return [object] }
        return []
    }
}

struct AudioscrobblerCallError: Error {
    let code: Int
    let message: String
    var scrobbleError: ScrobbleError { AudioscrobblerAPI.mapError(code: code, message: message) }
}

extension Error {
    /// Converts any error thrown by `AudioscrobblerAPI.call` into a `ScrobbleError`.
    var audioscrobblerError: ScrobbleError {
        if let call = self as? AudioscrobblerCallError { return call.scrobbleError }
        return asScrobbleError
    }
}
