import AppKit
import ScrobbleCore
import ShazamLibrary
import SwiftUI

/// Guides the user to grant Full Disk Access (§6.5). While open, the scheduler polls readability every 2 s, so the
/// status row flips to "Access works" without a relaunch when the grant takes effect.
@MainActor
final class AccessSetupWindowController: NSWindowController, NSWindowDelegate {
    private let scheduler: RescanScheduler

    init(model: AppModel, scheduler: RescanScheduler) {
        self.scheduler = scheduler
        let window = NSWindow(contentViewController: NSHostingController(rootView: AccessSetupView(model: model)))
        window.title = String(localized: "Let ShazamScrobbler Read Shazam")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show() {
        scheduler.setFastPolling(true)
        NSApp.activateApp()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        scheduler.setFastPolling(false)
    }
}

struct AccessSetupView: View {
    @ObservedObject var model: AppModel
    @State private var deniedSince = Date()

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
    private static let securityURL = URL(string: "https://github.com/ShazamScrobbler/macos-app/blob/master/SECURITY.md")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "macOS only lets apps read Shazam's history with Full Disk Access."))
                .font(.headline)
            Text(String(localized: "ShazamScrobbler reads one file, read-only:"))
            Text((model.library.databaseURL.path as NSString).abbreviatingWithTildeInPath)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Link(String(localized: "What we read and how to verify it"), destination: Self.securityURL)

            Divider()

            HStack(alignment: .top, spacing: 16) {
                appIcon
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "1. Click Open Full Disk Access Settings."))
                    Text(String(localized: "2. Drag this icon into the list, or click + and choose ShazamScrobbler in Applications."))
                    Text(String(localized: "3. Make sure the switch next to ShazamScrobbler is on."))
                }
            }
            Button(String(localized: "Open Full Disk Access Settings")) { NSWorkspace.shared.open(Self.settingsURL) }
                .keyboardShortcut(.defaultAction)

            statusRow
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: model.snapshot.libraryStatus) { status in
            if status == .accessDenied { deniedSince = Date() }
        }
    }

    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
            .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
            .help(String(localized: "Drag into the Full Disk Access list"))
            .accessibilityLabel(String(localized: "ShazamScrobbler app icon, drag into the Full Disk Access list"))
    }

    @ViewBuilder private var statusRow: some View {
        switch model.snapshot.libraryStatus {
        case .ok, .noLibraryYet:
            Label(String(localized: "Access works. You can close this window."), systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .accessDenied:
            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "No access yet. This updates by itself."), systemImage: "hourglass")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if context.date.timeIntervalSince(deniedSince) > 5 {
                        Button(String(localized: "Already switched on? Relaunch ShazamScrobbler")) { Self.relaunch() }
                    }
                }
            }
        case let .unsupportedSchema(detail):
            Label(String(localized: "Access works, but this Shazam version isn't supported yet (\(detail))."),
                  systemImage: "exclamationmark.triangle").foregroundColor(.orange)
        case .notInstalled:
            Label(String(localized: "Shazam isn't installed."), systemImage: "exclamationmark.triangle").foregroundColor(.orange)
        case let .unreadable(detail):
            Label(detail, systemImage: "exclamationmark.triangle").foregroundColor(.orange)
        }
    }

    /// Starts a detached shell that waits for this process to exit, then opens a new instance. The bundle path is
    /// passed as `$0`, never interpolated into the script.
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; exec /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
