import Foundation
import os

/// Watches a directory and named files inside it; re-arms after deletes, renames and
/// permission failures. All state lives on a private serial queue.
public final class FolderWatcher: @unchecked Sendable {
    private let directory: URL
    private let fileNames: [String]
    private let debounce: TimeInterval
    private let rearmInterval: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "ShazamScrobbler.FolderWatcher")
    private static let log = Logger(subsystem: "ShazamScrobbler", category: "shazam")

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]
    private var rearmTimer: DispatchSourceTimer?
    private var pending: DispatchWorkItem?
    private var stopped = true
    private var loggedErrors: [String: Int32] = [:]

    /// `onChange` runs on the watcher's private queue. Never call `stop()` (or read
    /// `isWatchingDirectory`) from inside it: both use `queue.sync` and would deadlock.
    public init(directory: URL, fileNames: [String], debounce: TimeInterval = 0.5, rearmInterval: TimeInterval = 5,
                onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.fileNames = fileNames
        self.debounce = debounce
        self.rearmInterval = rearmInterval
        self.onChange = onChange
    }

    public var isWatchingDirectory: Bool {
        dispatchPrecondition(condition: .notOnQueue(queue))
        return queue.sync { directorySource != nil }
    }

    public func start() {
        queue.async {
            self.stopped = false
            self.arm()
        }
    }

    /// Blocks until the watcher's queue has torn everything down. Do not call from `onChange`.
    public func stop() {
        dispatchPrecondition(condition: .notOnQueue(queue))
        queue.sync {
            stopped = true
            cancelAll()
        }
    }

    deinit {
        // Handlers hold `self` weakly, so none can be running here. Cancelling closes the fds.
        directorySource?.cancel()
        fileSources.values.forEach { $0.cancel() }
        rearmTimer?.cancel()
        pending?.cancel()
    }

    private func arm() {
        guard !stopped else { return }
        if directorySource == nil {
            directorySource = makeSource(path: directory.path) { [weak self] flags in self?.directoryChanged(flags) }
        }
        if directorySource != nil {
            for name in fileNames where fileSources[name] == nil {
                fileSources[name] = makeSource(path: directory.appendingPathComponent(name).path) { [weak self] flags in
                    self?.fileChanged(name, flags)
                }
            }
        }
        // A missing file inside a watched directory is reported by the directory's own event,
        // so only an unwatched directory needs polling.
        if directorySource == nil { scheduleRearm() } else { cancelRearm() }
    }

    private func makeSource(path: String, handler: @escaping @Sendable (DispatchSource.FileSystemEvent) -> Void)
        -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            let code = errno
            if code != ENOENT, loggedErrors[path] != code {
                Self.log.notice("Cannot watch \(path, privacy: .private): errno \(code)")
            }
            loggedErrors[path] = code
            return nil
        }
        loggedErrors[path] = nil
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib, .link, .revoke], queue: queue)
        source.setEventHandler { [weak source] in
            guard let source else { return }
            handler(source.data)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func directoryChanged(_ flags: DispatchSource.FileSystemEvent) {
        if !flags.isDisjoint(with: [.delete, .rename, .revoke]) {
            cancelAll()
        }
        arm()
        fire()
    }

    private func fileChanged(_ name: String, _ flags: DispatchSource.FileSystemEvent) {
        if !flags.isDisjoint(with: [.delete, .rename, .revoke]) {
            fileSources.removeValue(forKey: name)?.cancel()
            arm()
        }
        fire()
    }

    private func fire() {
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func scheduleRearm() {
        guard rearmTimer == nil, !stopped else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + rearmInterval, repeating: rearmInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let hadDirectory = self.directorySource != nil
            let hadFiles = self.fileSources.count
            self.arm()
            if (!hadDirectory && self.directorySource != nil) || self.fileSources.count > hadFiles { self.fire() }
        }
        rearmTimer = timer
        timer.resume()
    }

    private func cancelRearm() {
        rearmTimer?.cancel()
        rearmTimer = nil
    }

    private func cancelAll() {
        directorySource?.cancel()
        directorySource = nil
        fileSources.values.forEach { $0.cancel() }
        fileSources = [:]
        cancelRearm()
        pending?.cancel()
    }
}
