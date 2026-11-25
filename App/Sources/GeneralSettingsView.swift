import ScrobbleCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            if LaunchAtLogin.isSupported {
                Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do { try LaunchAtLogin.set(enabled); launchError = nil }
                        catch { launchError = error.localizedDescription; launchAtLogin = LaunchAtLogin.isEnabled }
                    }
                if LaunchAtLogin.requiresApproval || launchError != nil {
                    Button(String(localized: "Approve in Login Items Settings…")) { LaunchAtLogin.openSystemSettings() }
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

            Toggle(String(localized: "Notify me when a song is detected (with a Don't Scrobble button)"),
                   isOn: $model.notifyNowPlaying)

            if updater.canCheck {
                Toggle(String(localized: "Automatically check for updates"), isOn: $updater.automaticallyChecks)
            }
        }
    }
}
