import AppKit
import Combine
import Foundation
import os
import ScrobbleClients
import ScrobbleCore
import ShazamLibrary

/// Owns the engine and the published state. Everything that touches the state database or the Keychain runs on
/// `storeQueue` (a private serial queue), never on the main actor. The user-action methods (`skipWaiting`,
/// `setChoice`, `removeAccount`, `accountSignedIn`, `reloadAccounts`) are fire-and-forget: they return at once and
/// trigger a rescan when the work is done. Work is queued in call order. `removeFromListenBrainz` is `async`.
/// `accountSignedIn` and `removeAccount` change the configuration, so they are applied asynchronously at the start of
/// the next scan cycle (inside the rescan gate, never during a scan); callers can observe `accounts`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot = .empty
    @Published private(set) var accounts: [Account] = []
    @Published var settings: EngineSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.engineSettings = settings
            scheduleDebouncedRescan()
        }
    }
    @Published var notifyNowPlaying: Bool {
        didSet { settingsStore.notifyNowPlaying = notifyNowPlaying }
    }

    /// When the last scan finished (the menu skips its on-open rescan if this is recent).
    private(set) var lastScanFinished: Date?
    /// True once the first scan has finished, even if its snapshot equals the placeholder (so it published nothing).
    @Published private(set) var hasScanned = false

    let accountStore: AccountStore
    let stateStore: StateStore
    let library = ShazamLibrary()
    let transport = URLSessionTransport()

    private let settingsStore: SettingsStore
    private let scanCycle: ScanCycle
    private let gate = RescanGate()
    private let storeQueue = DispatchQueue(label: "ShazamScrobbler.store", qos: .userInitiated)
    private var scrobblers: [AccountID: any Scrobbler] = [:]
    private var configurationProblems: [AccountID: AccountProblem] = [:]
    private var reloadGeneration = 0
    private var reloadDiscarded = false
    private enum Mutation: Sendable {
        case remove(AccountID)
        case signedIn(Account)
    }
    private var pendingMutations: [Mutation] = []
    /// Accounts being removed: a reload that read the store before the removal ran must not resurrect them.
    private var removing: Set<AccountID> = []
    /// Set by a reconnect, wake or fixed account; consumed by the next scan, which then sends transient retries now.
    private var pendingRetryNow = false
    private var wakeTimer: Timer?
    private var settingsDebounce: Task<Void, Never>?
    private let log = Logger(subsystem: "ShazamScrobbler", category: "ui")

    init() throws {
        accountStore = AccountStore()
        settingsStore = SettingsStore()
        stateStore = try StateStore(url: StateStore.defaultURL)
        do {
            try LegacyMigration.migrateDefaults(defaults: .standard, accounts: accountStore, settings: settingsStore,
                                                store: stateStore, now: Date())
        } catch {
            // Converges on the next launch (the migration is ordered to be retried); not worth blocking the app.
            log.error("Legacy migration failed: \(String(describing: error), privacy: .private)")
        }
        settings = settingsStore.engineSettings
        notifyNowPlaying = settingsStore.notifyNowPlaying
        let time = SystemTime()
        scanCycle = ScanCycle(source: library, store: stateStore, delivery: Delivery(store: stateStore, time: time), time: time)
        reloadAccounts()
    }

    // MARK: off-main work

    private func onStoreQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        let queue = storeQueue
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: scanning

    private struct ScanInputs: Sendable {
        var accounts: [Account]
        var scrobblers: [AccountID: any Scrobbler]
        var settings: EngineSettings
        var retryNow: Bool
    }

    /// Takes (and clears) the pending retry-now request, so it is used by exactly one scan.
    private func takeScanInputs() -> ScanInputs {
        defer { pendingRetryNow = false }
        return ScanInputs(accounts: accounts, scrobblers: scrobblers, settings: settings, retryNow: pendingRetryNow)
    }

    /// Safe to call from anywhere, any number of times: scans are coalesced and serialized by the gate.
    /// `retryNow` (reconnect, wake): the scan also sends transient retries now instead of after their backoff (§7);
    /// it carries over to a coalesced scan.
    func rescan(retryNow: Bool = false) {
        if retryNow { pendingRetryNow = true }
        let gate = gate, cycle = scanCycle
        Task { [weak self] in
            await gate.trigger { [weak self] in
                await self?.applyPendingMutations()
                guard let inputs = await self?.takeScanInputs() else { return }
                let snapshot = await cycle.run(accounts: inputs.accounts, scrobblers: inputs.scrobblers,
                                               settings: inputs.settings, retryNow: inputs.retryNow)
                await self?.publish(snapshot)
            }
        }
    }

    private func scheduleDebouncedRescan() {
        settingsDebounce?.cancel()
        settingsDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    private func publish(_ new: Snapshot) {
        lastScanFinished = Date()
        var merged = new
        merged.problems.merge(configurationProblems) { held, _ in held }
        if merged != snapshot { snapshot = merged }
        if !hasScanned { hasScanned = true }
        scheduleWake(at: merged.nextWake)
    }

    private func scheduleWake(at date: Date?) {
        wakeTimer?.invalidate()
        wakeTimer = nil
        guard let date else { return }
        let timer = Timer(fire: max(date, Date().addingTimeInterval(0.5)), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        wakeTimer = timer
    }

    // MARK: accounts

    private struct LoadedAccounts: Sendable {
        var accounts: [Account]
        var scrobblers: [AccountID: any Scrobbler]
        var problems: [AccountID: AccountProblem]
    }

    /// Reads the accounts and builds their clients (Keychain reads) off the main actor, then rescans.
    func reloadAccounts() {
        reloadGeneration += 1
        let generation = reloadGeneration
        let store = accountStore, transport = transport
        Task { [weak self] in
            let loaded = await self?.onStoreQueue { () -> LoadedAccounts in
                var result = LoadedAccounts(accounts: store.load(), scrobblers: [:], problems: [:])
                for account in result.accounts {
                    switch ScrobblerFactory.make(for: account, accounts: store, transport: transport) {
                    case let .success(scrobbler): result.scrobblers[account.id] = scrobbler
                    case let .failure(problem): result.problems[account.id] = problem
                    }
                }
                return result
            }
            guard let self, let loaded else { return }
            guard generation == self.reloadGeneration else {
                self.reloadDiscarded = true   // a mutation came after this read started; redone once it is applied
                return
            }
            let gone = self.removing
            self.accounts = loaded.accounts.filter { !gone.contains($0.id) }
            self.scrobblers = loaded.scrobblers.filter { !gone.contains($0.key) }
            self.configurationProblems = loaded.problems.filter { !gone.contains($0.key) }
            self.rescan()
        }
    }

    /// After a successful (re-)sign-in or key change: saves the account, rebuilds its client and releases held
    /// scrobbles. Applied asynchronously at the start of the next scan cycle.
    func accountSignedIn(_ account: Account) {
        reloadGeneration += 1
        pendingMutations.append(.signedIn(account))
        rescan()
    }

    /// Applied asynchronously at the start of the next scan cycle; the UI reflects the removal at once.
    func removeAccount(_ id: AccountID) {
        reloadGeneration += 1
        scrobblers[id] = nil
        configurationProblems[id] = nil
        accounts.removeAll { $0.id == id }
        removing.insert(id)
        pendingMutations.append(.remove(id))
        rescan()
    }

    /// Runs at the start of every gate body, so no scan overlaps a configuration change and the next scan sees it.
    private func applyPendingMutations() async {
        guard !pendingMutations.isEmpty else { return }
        let batch = pendingMutations
        pendingMutations = []
        let accountStore = accountStore, stateStore = stateStore, transport = transport, log = log
        var removedInBatch: Set<AccountID> = []
        for mutation in batch {
            switch mutation {
            case let .remove(id):
                await onStoreQueue {
                    do {
                        try accountStore.remove(id)
                        try stateStore.removeAccount(id)
                    } catch {
                        log.error("Removing account failed: \(String(describing: error), privacy: .private)")
                    }
                }
                removedInBatch.insert(id)
                removing.remove(id)
                accounts.removeAll { $0.id == id }
                scrobblers[id] = nil
                configurationProblems[id] = nil
            case let .signedIn(account):
                // A removal of the same account (earlier in this batch, or still in flight) wins.
                if removedInBatch.contains(account.id) || removing.contains(account.id) { continue }
                let result = await onStoreQueue { () -> Result<any Scrobbler, AccountProblem> in
                    accountStore.upsert(account)
                    return ScrobblerFactory.make(for: account, accounts: accountStore, transport: transport)
                }
                if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account }
                else { accounts.append(account) }
                switch result {
                case let .success(scrobbler):
                    scrobblers[account.id] = scrobbler
                    configurationProblems[account.id] = nil
                case let .failure(problem):
                    scrobblers[account.id] = nil
                    configurationProblems[account.id] = problem
                }
                await onStoreQueue {
                    do { try stateStore.releaseHeld(account: account.id) }
                    catch { log.error("Releasing held scrobbles failed: \(String(describing: error), privacy: .private)") }
                }
                pendingRetryNow = true   // account fixed: this scan sends its retries now (§7)
            }
        }
        if reloadDiscarded {
            reloadDiscarded = false
            reloadAccounts()
        }
    }

    // MARK: user actions

    func togglePause() { settings.paused.toggle() }

    func skipWaiting() {
        let stateStore = stateStore, log = log
        Task { [weak self] in
            await self?.onStoreQueue {
                do { _ = try stateStore.skipAllWaiting(now: Date()) }
                catch { log.error("Skipping waiting scrobbles failed: \(String(describing: error), privacy: .private)") }
            }
            self?.rescan()
        }
    }

    /// `.force` is "Scrobble Anyway": also moves the tag's skipped and too-short rows to waiting, which works even after
    /// the account cursor has passed the tag (`StateStore.force`).
    func setChoice(_ choice: UserChoice?, for key: TagKey) {
        let stateStore = stateStore, log = log
        Task { [weak self] in
            await self?.onStoreQueue {
                do {
                    if choice == .force { try stateStore.force(key: key, now: Date()) }
                    else { try stateStore.setChoice(choice, for: key) }
                } catch { log.error("Saving the choice failed: \(String(describing: error), privacy: .private)") }
            }
            self?.rescan()
        }
    }

    func removeFromListenBrainz(row: SongRow, account: Account) async {
        let accountStore = accountStore, stateStore = stateStore, transport = transport, log = log
        let client: ListenBrainzClient? = await onStoreQueue {
            guard case let .success(scrobbler) = ScrobblerFactory.make(for: account, accounts: accountStore, transport: transport)
            else { return nil }
            return scrobbler as? ListenBrainzClient
        }
        guard let client else { return }
        do {
            try await client.remove(listenedAt: row.date, track: row.track)
            await onStoreQueue {
                do {
                    try stateStore.setChoice(.exclude, for: row.key)
                    try stateStore.set(.skipped(.user), key: row.key, account: account.id, now: Date())
                } catch {
                    log.error("Saving the removal failed: \(String(describing: error), privacy: .private)")
                }
            }
        } catch {
            log.error("Remove from ListenBrainz failed: \(String(describing: error), privacy: .private)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Couldn't remove “\(Formatting.songTitle(row.track))” from \(Formatting.accountName(account))")
            alert.informativeText = String(localized: "The listen is still on the server. Check your connection and try again.")
            NSApp.activateApp()
            alert.runModal()
        }
        rescan()
    }
}
