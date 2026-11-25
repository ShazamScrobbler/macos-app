import AppKit
import Combine
import ScrobbleCore

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    struct Actions {
        var openSettings: () -> Void
        var openAccessSetup: () -> Void
        var checkForUpdates: () -> Void
        var openAbout: () -> Void
    }

    private let model: AppModel
    private let actions: Actions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []
    private var countdownTimer: Timer?
    private let nowPlayingImage = NSImage(systemSymbolName: "waveform", accessibilityDescription: String(localized: "Now playing"))

    private let nowPlayingHeader = NSMenuItem()
    private let nowPlayingItem = NSMenuItem()
    private let nowPlayingSeparator = NSMenuItem.separator()
    private let recentHeader = NSMenuItem()
    private var recentItems: [NSMenuItem] = []
    private var problemItems: [NSMenuItem] = []
    private let recentSeparator = NSMenuItem.separator()
    private let problemSeparator = NSMenuItem.separator()
    private let libraryItem = NSMenuItem()
    private let warningImage = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: String(localized: "Problem"))
    private let waitingImage = NSImage(systemSymbolName: "hourglass", accessibilityDescription: String(localized: "Waiting"))
    private var shownNowPlaying: SongRow?
    private let pauseItem = NSMenuItem()
    private let skipItem = NSMenuItem()

    private var content = MenuContent(nowPlaying: nil, recent: [], problems: [], library: nil, paused: false, waitingCount: 0)
    private var shownRecent: [SongRow?] = []
    private var shownProblems: [ProblemRow?] = []

    init(model: AppModel, actions: Actions) {
        self.model = model
        self.actions = actions
        super.init()
        buildMenu()
        model.$snapshot
            .combineLatest(model.$accounts)
            .receive(on: DispatchQueue.main)   // not RunLoop.main: must update while the menu is open (#8)
            .sink { [weak self] snapshot, accounts in
                self?.apply(MenuModel.content(snapshot: snapshot, accounts: accounts))
            }
            .store(in: &cancellables)
    }

    // MARK: build once

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        configureHeader(nowPlayingHeader, String(localized: "Now Playing"))
        configureHeader(recentHeader, String(localized: "Recent"))
        [nowPlayingHeader, nowPlayingItem, nowPlayingSeparator].forEach { $0.isHidden = true; menu.addItem($0) }
        nowPlayingItem.isEnabled = false

        menu.addItem(recentHeader)
        recentItems = (0..<MenuModel.recentSlots).map { _ in
            let item = NSMenuItem()
            item.isHidden = true
            menu.addItem(item)
            return item
        }
        recentSeparator.isHidden = true
        menu.addItem(recentSeparator)
        problemItems = (0..<MenuModel.problemSlots).map { _ in
            let item = NSMenuItem(title: "", action: #selector(openSettingsAction), keyEquivalent: "")
            item.target = self
            item.image = warningImage
            item.isHidden = true
            menu.addItem(item)
            return item
        }
        libraryItem.isHidden = true
        libraryItem.target = self
        libraryItem.image = warningImage
        menu.addItem(libraryItem)
        problemSeparator.isHidden = true
        menu.addItem(problemSeparator)

        pauseItem.target = self
        pauseItem.action = #selector(togglePauseAction)
        pauseItem.keyEquivalent = "p"
        menu.addItem(pauseItem)
        skipItem.target = self
        skipItem.action = #selector(skipWaitingAction)
        skipItem.isHidden = true
        menu.addItem(skipItem)
        menu.addItem(.separator())

        addAction(String(localized: "Settings…"), #selector(openSettingsAction), key: ",")
        addAction(String(localized: "Check for Updates…"), #selector(checkForUpdatesAction))
        addAction(String(localized: "About ShazamScrobbler"), #selector(openAboutAction))
        menu.addItem(withTitle: String(localized: "Quit ShazamScrobbler"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        NotificationCenter.default.addObserver(self, selector: #selector(dayChanged), name: .NSCalendarDayChanged, object: nil)
        statusItem.menu = menu
        statusItem.button?.image = NSImage(named: "StatusIcon")
        statusItem.button?.imagePosition = .imageLeading
        apply(content)
    }

    private func configureHeader(_ item: NSMenuItem, _ title: String) {
        item.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
    }

    private func addAction(_ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    // MARK: apply (diffed)

    private func apply(_ new: MenuContent) {
        content = new

        let hasNowPlaying = new.nowPlaying != nil
        [nowPlayingHeader, nowPlayingItem, nowPlayingSeparator].forEach { $0.isHidden = !hasNowPlaying }
        if shownNowPlaying != new.nowPlaying?.row {
            shownNowPlaying = new.nowPlaying?.row
            nowPlayingItem.submenu = new.nowPlaying.map { submenu(for: $0.row) }
        }
        updateNowPlayingTitle()

        let newRecent: [SongRow?] = (0..<MenuModel.recentSlots).map { $0 < new.recent.count ? new.recent[$0] : nil }
        for index in MenuModel.changedSlots(old: shownRecent, new: newRecent) {
            configure(recentItems[index], with: newRecent[index])
        }
        shownRecent = newRecent
        recentHeader.isHidden = new.recent.isEmpty
        // Hidden when there are no recent rows: the now-playing separator (if any) already closes that block.
        recentSeparator.isHidden = new.recent.isEmpty

        let newProblems: [ProblemRow?] = (0..<MenuModel.problemSlots).map { $0 < new.problems.count ? new.problems[$0] : nil }
        for index in MenuModel.changedSlots(old: shownProblems, new: newProblems) {
            let item = problemItems[index]
            item.isHidden = newProblems[index] == nil
            item.title = newProblems[index].map(Formatting.problem) ?? ""
        }
        shownProblems = newProblems

        libraryItem.isHidden = new.library == nil
        problemSeparator.isHidden = new.problems.isEmpty && new.library == nil
        libraryItem.image = new.library == .waitingForShazam ? waitingImage : warningImage
        libraryItem.title = new.library.map(Formatting.library) ?? ""
        switch new.library {
        case .accessDenied?: libraryItem.action = #selector(openAccessSetupAction)
        case .notInstalled?: libraryItem.action = #selector(openShazamInAppStoreAction)
        default: libraryItem.action = nil
        }
        libraryItem.isEnabled = libraryItem.action != nil

        pauseItem.title = new.paused ? String(localized: "Resume Scrobbling") : String(localized: "Pause Scrobbling")
        skipItem.isHidden = new.waitingCount == 0
        skipItem.title = String(localized: "Skip \(new.waitingCount) Waiting")

        updateStatusButton()
    }

    private func configure(_ item: NSMenuItem, with row: SongRow?) {
        guard let row else {
            item.isHidden = true
            item.submenu = nil
            return
        }
        let full = Formatting.songTitle(row.track)
        item.isHidden = false
        item.title = "\(Formatting.truncateMiddle(full))   \(Formatting.time(row.date))"
        item.toolTip = full
        item.image = NSImage(systemSymbolName: Formatting.symbol(row.aggregate),
                             accessibilityDescription: Formatting.symbolDescription(row.aggregate))
        item.submenu = submenu(for: row)
    }

    private func submenu(for row: SongRow) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for line in row.lines {
            let item = NSMenuItem(title: "\(Formatting.accountName(line.account)): \(Formatting.state(line.state))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }
        if !row.lines.isEmpty { submenu.addItem(.separator()) }

        let toggle = NSMenuItem(title: row.isExcluded ? String(localized: "Scrobble Anyway") : String(localized: "Don't Scrobble"),
                                action: #selector(toggleChoiceAction(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.representedObject = row
        submenu.addItem(toggle)

        for line in row.lines {
            if line.account.preset.family == .listenBrainz, case .scrobbled? = line.state {
                let remove = NSMenuItem(title: String(localized: "Remove from \(Formatting.accountName(line.account))"),
                                        action: #selector(removeFromListenBrainzAction(_:)), keyEquivalent: "")
                remove.target = self
                remove.representedObject = (row, line.account)
                submenu.addItem(remove)
            }
            if line.account.preset == .lastfm || line.account.preset == .librefm {
                let open = NSMenuItem(title: String(localized: "Open \(Formatting.accountName(line.account)) Library"),
                                      action: #selector(openLibraryAction(_:)), keyEquivalent: "")
                open.target = self
                open.representedObject = line.account
                submenu.addItem(open)
            }
        }

        if row.lines.contains(where: { line in
            if case .retry? = line.state { return Formatting.isLocalNetwork(line.account.apiURL) }
            return false
        }) {
            let local = NSMenuItem(title: String(localized: "Can't reach a local server? Allow Local Network Access…"),
                                   action: #selector(openLocalNetworkSettingsAction), keyEquivalent: "")
            local.target = self
            submenu.addItem(local)
        }

        let copy = NSMenuItem(title: String(localized: "Copy “\(Formatting.songTitle(row.track))”"),
                              action: #selector(copyAction(_:)), keyEquivalent: "")
        copy.target = self
        copy.representedObject = Formatting.songTitle(row.track)
        submenu.addItem(copy)
        return submenu
    }

    private func updateNowPlayingTitle() {
        guard let nowPlaying = content.nowPlaying else { return }
        let title = Formatting.truncateMiddle(Formatting.songTitle(nowPlaying.row.track))
        let remaining = MenuModel.countdown(to: nowPlaying.deadline, now: Date())
        nowPlayingItem.title = String(localized: "\(title)   Scrobbles in \(remaining)")
        if nowPlayingItem.image !== nowPlayingImage { nowPlayingItem.image = nowPlayingImage }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let hasProblem = !content.problems.isEmpty || content.library == .accessDenied
            || content.library.map { if case .unsupported = $0 { true } else { false } } == true
        button.appearsDisabled = content.paused
        button.title = hasProblem ? " !" : (content.nowPlaying != nil ? " ♪" : "")
        let tip: String
        if hasProblem { tip = content.problems.first.map(Formatting.problem) ?? content.library.map(Formatting.library) ?? "" }
        else if content.paused { tip = String(localized: "ShazamScrobbler: paused") }
        else if let playing = content.nowPlaying { tip = String(localized: "Now playing: \(Formatting.songTitle(playing.row.track))") }
        else { tip = String(localized: "ShazamScrobbler") }
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        updateNowPlayingTitle()
        countdownTimer?.invalidate()
        if model.lastScanFinished.map({ Date().timeIntervalSince($0) > 10 }) ?? true { model.rescan() }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlayingTitle() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)   // keeps ticking while the menu is tracking
        countdownTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: actions

    @objc private func dayChanged() {
        // Row times read "today" vs a date: force every visible row (and submenu) to re-render once.
        shownRecent = []
        shownNowPlaying = nil
        apply(content)
    }

    @objc private func togglePauseAction() { model.togglePause() }
    @objc private func skipWaitingAction() { model.skipWaiting() }
    @objc private func openSettingsAction() { actions.openSettings() }
    @objc private func openAccessSetupAction() { actions.openAccessSetup() }
    @objc private func checkForUpdatesAction() { actions.checkForUpdates() }
    @objc private func openAboutAction() { actions.openAbout() }

    @objc private func openShazamInAppStoreAction() {
        if let url = URL(string: "macappstore://apps.apple.com/app/shazam/id897118787") { NSWorkspace.shared.open(url) }
    }

    @objc private func openLocalNetworkSettingsAction() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleChoiceAction(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? SongRow else { return }
        model.setChoice(row.isExcluded ? .force : .exclude, for: row.key)
    }

    @objc private func removeFromListenBrainzAction(_ sender: NSMenuItem) {
        guard let (row, account) = sender.representedObject as? (SongRow, Account) else { return }
        Task { await model.removeFromListenBrainz(row: row, account: account) }
    }

    @objc private func openLibraryAction(_ sender: NSMenuItem) {
        guard let account = sender.representedObject as? Account else { return }
        let host = account.preset == .librefm ? "libre.fm" : "www.last.fm"
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let user = account.username.addingPercentEncoding(withAllowedCharacters: allowed) ?? account.username
        if let url = URL(string: "https://\(host)/user/\(user)/library") { NSWorkspace.shared.open(url) }
    }

    @objc private func copyAction(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
