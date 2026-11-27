import Foundation
import Testing
@testable import ShazamLibrary

@Suite(.serialized) struct FolderWatcherTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func append(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("x".utf8))
        try handle.close()
    }

    @Test func firesWhenWatchedFileIsAppended() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let wal = dir.appendingPathComponent("db-wal")
        FileManager.default.createFile(atPath: wal.path, contents: Data())
        let counter = Counter()
        let watcher = FolderWatcher(directory: dir, fileNames: ["db-wal"], debounce: 0.05, rearmInterval: 0.2) { counter.bump() }
        watcher.start(); defer { watcher.stop() }
        #expect(await waitUntil { watcher.isWatchingDirectory })
        try append(wal)
        #expect(await waitUntil { counter.value >= 1 })
    }

    @Test func survivesDeleteAndRecreateOfWatchedFile() async throws {   // the #41 failure mode
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let wal = dir.appendingPathComponent("db-wal")
        FileManager.default.createFile(atPath: wal.path, contents: Data())
        let counter = Counter()
        let watcher = FolderWatcher(directory: dir, fileNames: ["db-wal"], debounce: 0.05, rearmInterval: 0.2) { counter.bump() }
        watcher.start(); defer { watcher.stop() }
        #expect(await waitUntil { watcher.isWatchingDirectory })
        try FileManager.default.removeItem(at: wal)
        FileManager.default.createFile(atPath: wal.path, contents: Data())
        try await Task.sleep(nanoseconds: 500_000_000)
        let before = counter.value
        try append(wal)
        #expect(await waitUntil { counter.value > before })
    }

    @Test func debouncesBursts() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let wal = dir.appendingPathComponent("db-wal")
        FileManager.default.createFile(atPath: wal.path, contents: Data())
        let counter = Counter()
        let watcher = FolderWatcher(directory: dir, fileNames: ["db-wal"], debounce: 0.3, rearmInterval: 0.2) { counter.bump() }
        watcher.start(); defer { watcher.stop() }
        #expect(await waitUntil { watcher.isWatchingDirectory })
        for _ in 0..<10 { try append(wal) }
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(counter.value == 1)
    }

    @Test func attachesWhenDirectoryAppearsLater() async throws {   // #36: no restart needed
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-late-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let counter = Counter()
        let watcher = FolderWatcher(directory: dir, fileNames: ["db-wal"], debounce: 0.05, rearmInterval: 0.2) { counter.bump() }
        watcher.start(); defer { watcher.stop() }
        #expect(watcher.isWatchingDirectory == false)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(await waitUntil { watcher.isWatchingDirectory })
        FileManager.default.createFile(atPath: dir.appendingPathComponent("db-wal").path, contents: Data())
        #expect(await waitUntil { counter.value >= 1 })
    }

    @Test func rearmIntervalGrowsToTheMaximumAndResetsOnAttach() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-backoff-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let counter = Counter()
        let watcher = FolderWatcher(directory: dir, fileNames: ["db-wal"], debounce: 0.05, rearmInterval: 0.05,
                                    maxRearmInterval: 0.2) { counter.bump() }
        watcher.start(); defer { watcher.stop() }
        #expect(await waitUntil { watcher.currentRearmInterval == 0.2 })
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(await waitUntil { watcher.isWatchingDirectory })
        #expect(await waitUntil { counter.value >= 1 })
        #expect(watcher.currentRearmInterval == 0.05)
    }

    /// Number of open fds of this process pointing inside `dir` (ignores other suites' fds).
    func openFDCount(in dir: URL) -> Int {
        let prefix = realpath(dir.path, nil).map { String(cString: $0) } ?? dir.path   // /var -> /private/var
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd")) ?? []
        return names.compactMap { Int32($0) }.filter { fd in
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return false }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).hasPrefix(prefix)
        }.count
    }

    @Test func releasingWatcherWithoutStopClosesDescriptors() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("db-wal").path, contents: Data())
        var watcher: FolderWatcher? = FolderWatcher(directory: dir, fileNames: ["db-wal"], debounce: 0.05, rearmInterval: 0.2) {}
        watcher?.start()
        #expect(await waitUntil { watcher?.isWatchingDirectory == true })
        #expect(openFDCount(in: dir) > 0)
        watcher = nil
        #expect(await waitUntil { openFDCount(in: dir) == 0 })
    }

    @Test func stopClosesDescriptors() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("db-wal").path, contents: Data())
        let watcher = FolderWatcher(directory: dir, fileNames: ["db-wal"], debounce: 0.05, rearmInterval: 0.2) {}
        watcher.start()
        #expect(await waitUntil { watcher.isWatchingDirectory })
        #expect(openFDCount(in: dir) > 0)
        watcher.stop()
        #expect(await waitUntil { openFDCount(in: dir) == 0 })
    }
}
