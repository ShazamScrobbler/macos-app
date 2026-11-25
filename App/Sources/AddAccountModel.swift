import AppKit
import ScrobbleClients
import ScrobbleCore

enum AddAccountMode: Identifiable {
    case add
    case reauthenticate(Account)
    case changeKey(Account)

    var id: String {
        switch self {
        case .add: "add"
        case let .reauthenticate(a): "reauth-\(a.id.rawValue)"
        case let .changeKey(a): "key-\(a.id.rawValue)"
        }
    }

    var existing: Account? {
        switch self {
        case .add: nil
        case let .reauthenticate(a), let .changeKey(a): a
        }
    }
}

/// Drives the Add Account sheet. Secrets (session key, token, API key, password) are never logged and never put in
/// error text; the password is cleared as soon as it has been used. Keychain writes run off the main actor.
@MainActor
final class AddAccountModel: ObservableObject {
    enum Phase: Equatable {
        case editing
        case waitingForBrowser
        case working
        case failed(String)
        case done(String)
    }

    @Published var preset: ServicePreset = .lastfm
    @Published var serverURL = ""
    @Published var keyMode: KeyMode = BuiltInLastFmKey.current == nil ? .own : .builtIn
    @Published var apiKey = ""
    @Published var apiSecret = ""
    @Published var token = ""
    @Published var username = ""
    @Published var password = ""
    @Published var usePassword = false
    @Published private(set) var phase: Phase = .editing

    let mode: AddAccountMode
    private let appModel: AppModel
    private var task: Task<Void, Never>?
    /// Bumped on every start and cancel, so a task that was cancelled never writes the phase afterwards.
    private var generation = 0

    init(mode: AddAccountMode, appModel: AppModel) {
        self.mode = mode
        self.appModel = appModel
        if let account = mode.existing {
            preset = account.preset
            serverURL = account.apiURL.absoluteString
            keyMode = { if case .changeKey = mode { return .own } else { return account.keyMode } }()
            username = account.username
        }
    }

    var builtInKeyAvailable: Bool { preset == .lastfm && BuiltInLastFmKey.current != nil }
    var needsServerURL: Bool { preset == .customAudioscrobbler || preset == .customListenBrainz }
    var supportsWebAuth: Bool { preset.defaultWebAuthURL != nil }
    var isBusy: Bool { phase == .working || phase == .waitingForBrowser }

    /// A custom server typed as `http://`: the session key or token would travel unencrypted.
    var showsInsecureServerWarning: Bool {
        needsServerURL && serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http://")
    }

    private var apiURL: URL? {
        guard needsServerURL else { return preset.defaultAPIURL }
        let text = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return nil }
        return url
    }

    private var credentials: (key: String, secret: String)? {
        if keyMode == .builtIn, builtInKeyAvailable { return BuiltInLastFmKey.current }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty || secret.isEmpty ? nil : (key, secret)
    }

    /// Cancels sign-in in progress and goes back to editing, with no error. A finished or failed sheet is left alone.
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        if isBusy { phase = .editing }
    }

    func signInWithBrowser() {
        guard let apiURL, let credentials, let webAuth = preset.defaultWebAuthURL else {
            phase = .failed(String(localized: "Fill in the server and API key first."))
            return
        }
        let auth = AudioscrobblerAuth(apiURL: apiURL, apiKey: credentials.key, apiSecret: credentials.secret,
                                      transport: appModel.transport)
        start { [self] in
            let token = try await auth.getToken()
            try Task.checkCancellation()
            NSWorkspace.shared.open(auth.authorizationURL(webAuthURL: webAuth, token: token))
            phase = .waitingForBrowser
            let deadline = Date().addingTimeInterval(300)
            while Date() < deadline {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                do {
                    let session = try await auth.getSession(token: token)
                    try Task.checkCancellation()
                    return try await finish(audioscrobbler: session, apiURL: apiURL, webAuth: webAuth, credentials: credentials)
                } catch AudioscrobblerAuthError.notAuthorizedYet {
                    continue
                }
            }
            throw SignInError.timedOut
        }
    }

    func signInWithPassword() {
        guard let apiURL, let credentials else {
            phase = .failed(String(localized: "Fill in the server and API key first."))
            return
        }
        guard apiURL.scheme?.lowercased() == "https" else {
            phase = .failed(Self.httpsRequired)
            return
        }
        let auth = AudioscrobblerAuth(apiURL: apiURL, apiKey: credentials.key, apiSecret: credentials.secret,
                                      transport: appModel.transport)
        let (user, pass) = (username, password)
        password = ""
        start { [self] in
            let session = try await auth.getMobileSession(username: user, password: pass)
            try Task.checkCancellation()
            return try await finish(audioscrobbler: session, apiURL: apiURL, webAuth: preset.defaultWebAuthURL, credentials: credentials)
        }
    }

    func connectListenBrainz() {
        guard let apiURL else {
            phase = .failed(String(localized: "Enter the server address."))
            return
        }
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            phase = .failed(String(localized: "Enter your user token."))
            return
        }
        start { [self] in
            let name = try await ListenBrainzClient.validate(apiURL: apiURL, token: value, transport: appModel.transport)
            try Task.checkCancellation()
            let account = makeAccount(apiURL: apiURL, webAuth: nil, username: name, keyMode: .own)
            try await save([(.token, value)], for: account)
            return String(localized: "Signed in as \(name)")
        }
    }

    // MARK: internals

    private enum SignInError: Error { case timedOut }

    /// Runs one sign-in attempt. The result goes to `phase` unless the attempt was cancelled meanwhile.
    private func start(_ work: @escaping @MainActor () async throws -> String) {
        guard task == nil else { return }
        generation += 1
        let mine = generation
        phase = .working
        task = Task {
            let outcome: Phase
            do {
                outcome = .done(try await work())
            } catch is CancellationError {
                outcome = .editing
            } catch {
                outcome = Task.isCancelled ? .editing : .failed(Self.message(for: error))
            }
            guard mine == generation else { return }
            phase = outcome
            task = nil
        }
    }

    private func finish(audioscrobbler session: AudioscrobblerSession, apiURL: URL, webAuth: URL?,
                        credentials: (key: String, secret: String)) async throws -> String {
        let keyMode: KeyMode = self.keyMode == .builtIn && builtInKeyAvailable ? .builtIn : .own
        let account = makeAccount(apiURL: apiURL, webAuth: webAuth, username: session.username, keyMode: keyMode)
        try await save([(.sessionKey, session.sessionKey),
                        (.apiKey, keyMode == .own ? credentials.key : nil),
                        (.apiSecret, keyMode == .own ? credentials.secret : nil)], for: account)
        return String(localized: "Signed in as \(session.username)")
    }

    /// Writes the secrets off the main actor, then hands the account to the model. A new account whose write fails
    /// is cleaned up so no half-saved secrets stay behind.
    private func save(_ secrets: [(SecretField, String?)], for account: Account) async throws {
        let store = appModel.accountStore, id = account.id, isNew = mode.existing == nil
        try await Task.detached {
            do {
                for (field, value) in secrets { try store.setSecret(value, field, for: id) }
            } catch {
                if isNew { for field in SecretField.allCases { try? store.setSecret(nil, field, for: id) } }
                throw error
            }
        }.value
        appModel.accountSignedIn(account)
    }

    private func makeAccount(apiURL: URL, webAuth: URL?, username: String, keyMode: KeyMode) -> Account {
        Account(id: mode.existing?.id ?? .new(), preset: preset, username: username, apiURL: apiURL,
                webAuthURL: webAuth, keyMode: keyMode, addedAt: mode.existing?.addedAt ?? Date())
    }

    static let httpsRequired = String(localized: "Password sign-in needs an https:// server address, so your password is never sent unencrypted.")

    /// User-facing text for a failure. Never includes secrets: only server-provided messages and fixed strings.
    static func message(for error: Error) -> String {
        switch error {
        case SignInError.timedOut:
            return String(localized: "Sign-in timed out. Approve access in the browser within 5 minutes, then try again.")
        case AudioscrobblerAuthError.tokenExpired:
            return String(localized: "The sign-in link expired. Try again.")
        case let AudioscrobblerAuthError.invalidCredentials(message):
            return message
        case AudioscrobblerAuthError.notAuthorizedYet:
            return String(localized: "Access wasn't approved in the browser. Try again.")
        case let AudioscrobblerAuthError.failed(inner):
            return message(for: inner)
        case ScrobbleError.signedOut:
            return String(localized: "That token or session isn't valid.")
        case let ScrobbleError.keyUnusable(code):
            return String(localized: "The API key was rejected (error \(code)). Last.fm may require Pro for this key; use your own key.")
        case let ScrobbleError.permanent(message):
            return message.hasPrefix("Password sign-in requires an https") ? httpsRequired : message
        case let ScrobbleError.transient(message):
            return message
        case ScrobbleError.rateLimited:
            return String(localized: "The server is rate limiting requests. Try again in a minute.")
        case is KeychainError:
            return String(localized: "Couldn't save the sign-in to the Keychain.")
        default:
            return error.localizedDescription
        }
    }
}
