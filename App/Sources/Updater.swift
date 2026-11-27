import Foundation
import Sparkle

@MainActor
final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController?

    init() {
        // Builds without a public EdDSA key (local dev) can't verify updates, so don't start Sparkle.
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        controller = key.isEmpty ? nil
            : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var canCheck: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}
