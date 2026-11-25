import AppKit
import SwiftUI

enum SettingsTab: Hashable { case general, accounts }

final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab = .general
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let selection = SettingsSelection()

    init(model: AppModel, updater: Updater) {
        let root = SettingsView(model: model, updater: updater, selection: selection)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = String(localized: "ShazamScrobbler Settings")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(tab: SettingsTab? = nil) {
        if let tab { selection.tab = tab }
        NSApp.activateApp()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettingsView(model: model, updater: updater)
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AccountsSettingsView(model: model)
                .tabItem { Label(String(localized: "Accounts"), systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}
