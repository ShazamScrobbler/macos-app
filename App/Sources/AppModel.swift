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
    private var wakeTimer: Timer?
    private var settingsDebounce: Task<Void, Never>?
    private let log = Logger(subsystem: "ShazamScrobbler", category: "ui")

    init() throws {
        accountStore = AccountStore()
        settingsStore = SettingsStore()
        stateStore = try StateStore(url: StateStore.defaultURL)
        try LegacyMigration.migrateDefaults(defaults: .standard, accounts: accountStore, settings: settingsStore,
                                            store: stateStore, now: Date())
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
    }

    private func scanInputs() -> ScanInputs {
        ScanInputs(accounts: accounts, scrobblers: scrobblers, settings: settings)
    }

    /// Safe to call from anywhere, any number of times: scans are coalesced and serialized by the gate.
    func rescan() {
        let gate = gate, cycle = scanCycle
        Task { [weak self] in
            await gate.trigger { [weak self] in
                guard let inputs = await self?.scanInputs() else { return }
                let snapshot = await cycle.run(accounts: inputs.accounts, scrobblers: inputs.scrobblers, settings: inputs.settings)
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
        var merged = new
        merged.problems.merge(configurationProblems) { held, _ in held }
        if merged != snapshot { snapshot = merged }
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
            guard let self, let loaded, generation == self.reloadGeneration else { return }
            self.accounts = loaded.accounts
            self.scrobblers = loaded.scrobblers
            self.configurationProblems = loaded.problems
            self.rescan()
        }
    }

    /// After a successful (re-)sign-in or key change: release held scrobbles and reload clients.
    func accountSignedIn(_ account: Account) {
        let accountStore = accountStore, stateStore = stateStore
        Task { [weak self] in
            await self?.onStoreQueue {
                accountStore.upsert(account)
                try? stateStore.releaseHeld(account: account.id)
            }
            self?.reloadAccounts()
        }
    }

    func removeAccount(_ id: AccountID) {
        // Stop delivering for it right away; the store cleanup follows off the main actor.
        scrobblers[id] = nil
        accounts.removeAll { $0.id == id }
        let accountStore = accountStore, stateStore = stateStore
        Task { [weak self] in
            let failure: String? = await self?.onStoreQueue {
                do {
                    try accountStore.remove(id)
                    try stateStore.removeAccount(id)
                    return nil
                } catch { return String(describing: error) }
            }
            if let failure { self?.log.error("Removing account failed: \(failure, privacy: .public)") }
            self?.reloadAccounts()
        }
    }

    // MARK: user actions

    func togglePause() { settings.paused.toggle() }

    func skipWaiting() {
        let stateStore = stateStore
        Task { [weak self] in
            await self?.onStoreQueue { _ = try? stateStore.skipAllWaiting(now: Date()) }
            self?.rescan()
        }
    }

    func setChoice(_ choice: UserChoice?, for key: TagKey) {
        let stateStore = stateStore
        Task { [weak self] in
            await self?.onStoreQueue { try? stateStore.setChoice(choice, for: key) }
            self?.rescan()
        }
    }

    func removeFromListenBrainz(row: SongRow, account: Account) async {
        let accountStore = accountStore, stateStore = stateStore, transport = transport
        let client: ListenBrainzClient? = await onStoreQueue {
            guard case let .success(scrobbler) = ScrobblerFactory.make(for: account, accounts: accountStore, transport: transport)
            else { return nil }
            return scrobbler as? ListenBrainzClient
        }
        guard let client else { return }
        do {
            try await client.remove(listenedAt: row.date, track: row.track)
            await onStoreQueue {
                try? stateStore.setChoice(.exclude, for: row.key)
                try? stateStore.set(.skipped(.user), key: row.key, account: account.id, now: Date())
            }
        } catch {
            log.error("Remove from ListenBrainz failed: \(String(describing: error), privacy: .public)")
        }
        rescan()
    }
}
