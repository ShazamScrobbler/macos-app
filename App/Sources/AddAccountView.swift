import AppKit
import ScrobbleCore
import SwiftUI

struct AddAccountView: View {
    @StateObject var model: AddAccountModel
    var onClose: () -> Void

    init(model: AddAccountModel, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form {
                if case .add = model.mode {
                    Picker(String(localized: "Service"), selection: $model.preset) {
                        ForEach(ServicePreset.allCases, id: \.self) { Text(Formatting.serviceName($0)).tag($0) }
                    }
                }
                if model.needsServerURL {
                    TextField(String(localized: "Server address"), text: $model.serverURL,
                              prompt: Text(verbatim: model.preset == .customListenBrainz ? "https://maloja.example.com/apis/listenbrainz" : "https://scrobbler.example.com/2.0/"))
                    if model.showsHTTPSRequired {
                        Label(AddAccountModel.httpsRequired, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.showsInsecureServerWarning {
                        Label(String(localized: "This server isn't encrypted. Your session key or token will be sent in plain text on your network."),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.preset.family == .audioscrobbler { audioscrobblerFields } else { listenBrainzFields }
            }
            .disabled(model.isBusy)
            status
            HStack {
                Spacer()
                if model.isBusy {
                    Button(String(localized: "Cancel")) { model.cancel() }
                }
                Button(isDone ? String(localized: "Done") : String(localized: "Close")) { model.cancel(); onClose() }
                    .keyboardShortcut(isDone ? .defaultAction : .cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onDisappear { model.cancel() }
    }

    private var isDone: Bool { if case .done = model.phase { true } else { false } }

    private var title: String {
        switch model.mode {
        case .add: String(localized: "Add Account")
        case .reauthenticate: String(localized: "Sign In Again")
        case .changeKey: String(localized: "Use Your Own API Key")
        }
    }

    @ViewBuilder private var audioscrobblerFields: some View {
        if model.builtInKeyAvailable {
            Picker(String(localized: "API key"), selection: $model.keyMode) {
                Text(String(localized: "ShazamScrobbler's key")).tag(KeyMode.builtIn)
                Text(String(localized: "My own key")).tag(KeyMode.own)
            }
            .pickerStyle(.radioGroup)
        }
        if model.keyMode == .own || !model.builtInKeyAvailable {
            TextField(String(localized: "API key"), text: $model.apiKey)
            SecureField(String(localized: "Shared secret"), text: $model.apiSecret)
            Link(String(localized: "Get an API key…"), destination: URL(string: "https://www.last.fm/api/account/create")!)
        }
        if model.supportsWebAuth && !model.usePassword {
            Button(String(localized: "Sign In with Browser")) { model.signInWithBrowser() }
            Button(String(localized: "Sign in with password instead")) { model.usePassword = true }.buttonStyle(.link)
        } else {
            TextField(String(localized: "Username"), text: $model.username)
            SecureField(String(localized: "Password"), text: $model.password)
            Button(String(localized: "Sign In")) { model.signInWithPassword() }
            Text(String(localized: "Your password is sent once over HTTPS to get a session and is never stored."))
                .font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder private var listenBrainzFields: some View {
        SecureField(String(localized: "User token"), text: $model.token)
        if model.preset == .listenbrainz {
            Link(String(localized: "Get your token…"), destination: URL(string: "https://listenbrainz.org/settings/")!)
        }
        Button(String(localized: "Connect")) { model.connectListenBrainz() }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .editing: EmptyView()
        case .working: ProgressView().controlSize(.small)
        case .waitingForBrowser:
            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "Approve ShazamScrobbler in your browser. This window updates by itself."),
                      systemImage: "safari")
                if let link = model.authorizationLink {
                    Text(String(localized: "The browser didn't open. Copy this link and open it yourself:"))
                        .font(.caption).foregroundColor(.secondary)
                    Text(verbatim: link.absoluteString).font(.caption).lineLimit(2).textSelection(.enabled)
                    Button(String(localized: "Copy Link")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link.absoluteString, forType: .string)
                    }
                }
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundColor(.orange)
        case let .done(message):
            Label(message, systemImage: "checkmark.circle").foregroundColor(.green)
        }
    }
}
