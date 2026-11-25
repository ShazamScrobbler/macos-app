import Combine
import ScrobbleCore
import UserNotifications

/// Now-playing and problem notifications. Content is artist/title and account problems only, never credentials.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let category = "NOW_PLAYING"
    private nonisolated static let dontScrobble = "DONT_SCROBBLE"

    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []
    private var lastNotifiedTag: TagKey?
    private var lastProblems: [AccountID: AccountProblem] = [:]
    private var seededProblems = false

    init(model: AppModel) {
        self.model = model
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let action = UNNotificationAction(identifier: Self.dontScrobble, title: String(localized: "Don't Scrobble"))
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [action],
                                                                 intentIdentifiers: [])])
        // Ask only when the user turns the setting on (not for an already-enabled setting at launch).
        model.$notifyNowPlaying
            .dropFirst()
            .removeDuplicates()
            .filter { $0 }
            .sink { _ in center.requestAuthorization(options: [.alert]) { _, _ in } }
            .store(in: &cancellables)
        model.$snapshot
            .dropFirst()   // the replayed placeholder; the next value is the first real scan
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handle($0) }
            .store(in: &cancellables)
    }

    private func handle(_ snapshot: Snapshot) {
        if model.notifyNowPlaying, let playing = snapshot.nowPlaying, playing.tag.key != lastNotifiedTag {
            lastNotifiedTag = playing.tag.key
            let content = UNMutableNotificationContent()
            content.title = playing.tag.track.title
            content.body = String(localized: "\(playing.tag.track.artist) — tap Don't Scrobble to skip it")
            content.categoryIdentifier = Self.category
            content.userInfo = ["tag": playing.tag.key.rawValue]
            post(content, id: playing.tag.key.rawValue)
        }
        // Seed from the first snapshot without posting: notify on change only, not at every launch.
        if !seededProblems {
            seededProblems = true
            lastProblems = snapshot.problems
        }
        // Once per state change: only problems that are new or changed since the previous snapshot.
        for (id, problem) in snapshot.problems where lastProblems[id] != problem {
            guard let account = model.accounts.first(where: { $0.id == id }) else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "ShazamScrobbler needs attention")
            content.body = Formatting.problem(ProblemRow(account: account, problem: problem))
            post(content, id: "problem-\(id.rawValue)")
        }
        lastProblems = snapshot.problems
    }

    private func post(_ content: UNMutableNotificationContent, id: String) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let raw = response.notification.request.content.userInfo["tag"] as? String
        completionHandler()
        if action == Self.dontScrobble, let raw {
            Task { @MainActor in self.model.setChoice(.exclude, for: TagKey(rawValue: raw)) }
        }
    }
}
