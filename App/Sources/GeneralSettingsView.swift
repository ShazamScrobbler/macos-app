import AppKit
import os
import ScrobbleCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    @State private var launchState = LaunchAtLogin.state
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    private static let log = Logger(subsystem: "ShazamScrobbler", category: "ui")

    var body: some View {
        Form {
            if LaunchAtLogin.isSupported {
                Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        // Skip when the toggle merely mirrors the system state (refresh or revert after an error).
                        guard enabled != (launchState == .enabled) else { return }
                        do { try LaunchAtLogin.set(enabled); launchError = nil }
                        catch {
                            Self.log.error("Launch at login failed: \(String(describing: error), privacy: .private)")
                            launchError = error.localizedDescription
                        }
                        refreshLaunchState()
                    }
                    .onAppear { refreshLaunchState() }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        refreshLaunchState()
                    }
                if let launchError {
                    Text(String(localized: "Couldn't change launch at login: \(launchError)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if launchState == .requiresApproval {
                    Button(String(localized: "Approve in Login Items Settings…")) { LaunchAtLogin.openSystemSettings() }
                } else if launchError != nil {
                    Button(String(localized: "Open Login Items Settings…")) { LaunchAtLogin.openSystemSettings() }
                }
            } else {
                Button(String(localized: "Open Login Items Settings…")) { LaunchAtLogin.openSystemSettings() }
            }

            Picker(String(localized: "While paused"), selection: $model.settings.pauseMode) {
                Text(String(localized: "Ignore new Shazam tags")).tag(PauseMode.ignore)
                Text(String(localized: "Keep them and send when resumed")).tag(PauseMode.keep)
            }

            Stepper(value: $model.settings.minPlayTime, in: EngineSettings.minPlayTimeRange, step: 15) {
                Text(String(localized: "Scrobble after a song plays for \(Int(model.settings.minPlayTime)) seconds"))
            }

            Toggle(String(localized: "Show notifications for detected songs (with a Don't Scrobble button) and account problems"),
                   isOn: $model.notifyNowPlaying)

            if updater.canCheck {
                Toggle(String(localized: "Automatically check for updates"), isOn: $updater.automaticallyChecks)
            }
        }
    }

    private func refreshLaunchState() {
        launchState = LaunchAtLogin.state
        launchAtLogin = launchState == .enabled
    }
}
