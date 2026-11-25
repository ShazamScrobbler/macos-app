import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!
    private var scheduler: RescanScheduler!
    private var menuController: MenuController?

    /// No nib or storyboard (and no NSPrincipalClass), so `@main` alone would never install the delegate.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            model = try AppModel()
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "ShazamScrobbler can't open its data")
            alert.informativeText = String(localized: "It keeps its state in ~/Library/Application Support/ShazamScrobbler. Error: \(String(describing: error))")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        scheduler = RescanScheduler(model: model)
        scheduler.start()
        menuController = MenuController(model: model, actions: .init(
            openSettings: { [weak self] in self?.openSettings() },
            openAccessSetup: { [weak self] in self?.openAccessSetup() },
            checkForUpdates: {},
            openAbout: { NSApp.activateApp(); NSApp.orderFrontStandardAboutPanel(nil) }))
    }

    func openSettings() {}
    func openAccessSetup() {}
}
