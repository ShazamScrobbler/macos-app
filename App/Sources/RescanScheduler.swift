import AppKit
import Network
import ShazamLibrary

/// Every reason to rescan (§4): Shazam folder changes, a 300 s safety-net timer, wake, network back, and a cheap
/// readability probe while the Full Disk Access window is open. The model coalesces them. Wake and network back
/// also send transient retries at once (§7).
///
/// The safety-net timer skips its scan when neither the Shazam database nor its -wal file changed since the last
/// scan and no wake is due (the model's `nextWake`). Folder, wake and network triggers always rescan.
@MainActor
final class RescanScheduler {
    private struct Fingerprint: Equatable {
        var database: Date?
        var wal: Date?
    }

    private let model: AppModel
    private var watcher: FolderWatcher?
    private var timer: Timer?
    private var fastTimer: Timer?
    private let pathMonitor = NWPathMonitor()
    private var wasOnline = true
    private var lastScan: Fingerprint?
    private var wasReadable = false

    init(model: AppModel) { self.model = model }

    func start() {
        let library = model.library
        let watcher = FolderWatcher(directory: library.watchedDirectoryURL, fileNames: ShazamLibrary.watchedFileNames) { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        watcher.start()
        self.watcher = watcher

        timer = makeTimer(every: 300) { [weak self] in self?.safetyNet() }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scan(retryNow: true) }
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if online && !self.wasOnline { self.scan(retryNow: true) }
                self.wasOnline = online
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "ShazamScrobbler.network"))
    }

    /// While on, every 2 s only checks whether the Shazam database's readability changed (granted or revoked), and rescans once when it did.
    func setFastPolling(_ on: Bool) {
        fastTimer?.invalidate()
        fastTimer = nil
        guard on else { return }
        wasReadable = model.library.isReadable()
        fastTimer = makeTimer(every: 2) { [weak self] in
            guard let self else { return }
            let readable = self.model.library.isReadable()
            if readable != self.wasReadable { self.scan() }
            self.wasReadable = readable
        }
    }

    /// `retryNow` (wake, network back): transient retries are sent now instead of after their backoff (§7).
    private func scan(retryNow: Bool = false) {
        lastScan = fingerprint()
        model.rescan(retryNow: retryNow)
    }

    private func safetyNet() {
        if let lastScan, lastScan == fingerprint() {
            let wakeDue = model.snapshot.nextWake.map { $0 <= Date() } ?? false
            if !wakeDue { return }
        }
        scan()
    }

    private func fingerprint() -> Fingerprint {
        let directory = model.library.watchedDirectoryURL
        func modified(_ name: String) -> Date? {
            let url = directory.appendingPathComponent(name)
            return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        let names = ShazamLibrary.watchedFileNames
        return Fingerprint(database: names.first.flatMap(modified), wal: names.dropFirst().first.flatMap(modified))
    }

    private func makeTimer(every seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = seconds / 10
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
