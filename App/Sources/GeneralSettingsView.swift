import ScrobbleCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = false   // replaced by LaunchAtLogin in Task 22

    var body: some View {
        Form {
            Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)

            Picker(String(localized: "While paused"), selection: $model.settings.pauseMode) {
                Text(String(localized: "Ignore new Shazam tags")).tag(PauseMode.ignore)
                Text(String(localized: "Keep them and send when resumed")).tag(PauseMode.keep)
            }

            Stepper(value: $model.settings.minPlayTime, in: EngineSettings.minPlayTimeRange, step: 15) {
                Text(String(localized: "Scrobble after a song plays for \(Int(model.settings.minPlayTime)) seconds"))
            }

            Toggle(String(localized: "Notify me when a song is detected (with a Don't Scrobble button)"),
                   isOn: $model.notifyNowPlaying)
        }
    }
}
