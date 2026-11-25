import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!
    private var scheduler: RescanScheduler!
    private var statusItem: NSStatusItem?

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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(named: "StatusIcon")
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Quit ShazamScrobbler"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
