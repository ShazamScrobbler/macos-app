import ScrobbleCore
import SwiftUI

struct AccountsSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AccountID?
    @State private var sheet: AddAccountMode?
    @State private var pendingRemoval: Account?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $selection) {
                ForEach(model.accounts) { account in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Formatting.accountName(account))
                            Text(account.apiURL.host ?? "").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        health(for: account)
                    }
                    .tag(account.id)
                    .contextMenu {
                        Button(String(localized: "Sign In Again…")) { sheet = .reauthenticate(account) }
                        Button(String(localized: "Remove"), role: .destructive) { pendingRemoval = account }
                    }
                }
            }
            .frame(minHeight: 200)
            .overlay {
                if model.accounts.isEmpty {
                    Text(String(localized: "Add an account to start scrobbling your Shazam tags."))
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button { sheet = .add } label: { Image(systemName: "plus") }
                    .help(String(localized: "Add Account"))
                Button {
                    if let selection, let account = model.accounts.first(where: { $0.id == selection }) { pendingRemoval = account }
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    .help(String(localized: "Remove Account"))
                Spacer()
                if let id = selection, let account = model.accounts.first(where: { $0.id == id }) {
                    Button(String(localized: "Sign In Again…")) { sheet = .reauthenticate(account) }
                    if account.preset.family == .audioscrobbler && account.preset != .librefm {   // Libre.fm needs no key
                        Button(String(localized: "Use My Own Key…")) { sheet = .changeKey(account) }
                    }
                }
            }
        }
        .confirmationDialog(
            pendingRemoval.map { String(localized: "Remove \(Formatting.accountName($0))?") } ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible, presenting: pendingRemoval
        ) { account in
            Button(String(localized: "Remove"), role: .destructive) {
                model.removeAccount(account.id)
                if selection == account.id { selection = nil }
            }
        } message: { _ in
            Text(String(localized: "Its sign-in is removed from this Mac and nothing more is sent to it."))
        }
        .sheet(item: $sheet) { mode in
            AddAccountView(model: AddAccountModel(mode: mode, appModel: model)) { sheet = nil }
        }
    }

    @ViewBuilder
    private func health(for account: Account) -> some View {
        switch model.snapshot.problems[account.id] {
        case .signedOut?:
            Label(String(localized: "Signed out"), systemImage: "exclamationmark.triangle").foregroundColor(.orange)
        case .keyUnusable?:
            Label(account.keyMode == .builtIn && account.preset == .lastfm ? String(localized: "Key needs Last.fm Pro?") : String(localized: "Key not working"),
                  systemImage: "exclamationmark.triangle").foregroundColor(.orange)
        case nil:
            Label(String(localized: "OK"), systemImage: "checkmark.circle").foregroundColor(.green)
        }
    }
}
