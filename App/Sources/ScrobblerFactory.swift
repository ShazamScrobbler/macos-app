import Foundation
import ScrobbleClients
import ScrobbleCore

enum BuiltInLastFmKey {
    /// Injected at build time (App/Config); absent in builds without Secrets.xcconfig.
    static var current: (key: String, secret: String)? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "LastFmAPIKey") as? String,
              let secret = Bundle.main.object(forInfoDictionaryKey: "LastFmAPISecret") as? String,
              !key.isEmpty, !secret.isEmpty else { return nil }
        return (key, secret)
    }
}

/// Libre.fm accepts any API key and secret (it doesn't register applications), so it never asks for one (spec §6.3).
/// These fixed values only fill the protocol's required fields; they are not secrets.
enum LibreFmKey {
    static let current = (key: "ShazamScrobbler", secret: "ShazamScrobbler")
}

enum ScrobblerFactory {
    static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2"
    }

    static func make(for account: Account, accounts: AccountStore,
                     transport: any HTTPTransport) -> Result<any Scrobbler, AccountProblem> {
        switch account.preset.family {
        case .audioscrobbler:
            guard let credentials = apiCredentials(for: account, accounts: accounts) else { return .failure(.keyUnusable) }
            guard let session = accounts.secret(.sessionKey, for: account.id) else { return .failure(.signedOut) }
            return .success(AudioscrobblerClient(apiURL: account.apiURL, apiKey: credentials.key, apiSecret: credentials.secret,
                                                 sessionKey: session, username: account.username, transport: transport))
        case .listenBrainz:
            guard let token = accounts.secret(.token, for: account.id) else { return .failure(.signedOut) }
            return .success(ListenBrainzClient(apiURL: account.apiURL, token: token, username: account.username,
                                               transport: transport, clientVersion: clientVersion))
        }
    }

    static func apiCredentials(for account: Account, accounts: AccountStore) -> (key: String, secret: String)? {
        if account.preset == .librefm { return LibreFmKey.current }
        switch account.keyMode {
        case .builtIn: return BuiltInLastFmKey.current
        case .own:
            guard let key = accounts.secret(.apiKey, for: account.id),
                  let secret = accounts.secret(.apiSecret, for: account.id) else { return nil }
            return (key, secret)
        }
    }
}
