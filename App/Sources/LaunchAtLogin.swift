import AppKit
import ServiceManagement

/// macOS 13+: SMAppService. macOS 12: no API without a helper app, so we open Login Items settings.
/// Never enumerates login items (that's what triggered 1.x's network-volume prompt).
enum LaunchAtLogin {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    enum State: Equatable { case unsupported, enabled, requiresApproval, notRegistered, notFound }

    static var state: State {
        guard #available(macOS 13.0, *) else { return .unsupported }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        default: return .notRegistered
        }
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static var requiresApproval: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .requiresApproval }
        return false
    }

    static func set(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSystemSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.users") {
            NSWorkspace.shared.open(url)
        }
    }
}
