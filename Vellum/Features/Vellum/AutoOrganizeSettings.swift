import Foundation

enum SettingsKeys {
    static let autoOrganizeEnabled = "vellum.autoOrganize"

    static func isAutoOrganizeEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: autoOrganizeEnabled) == nil
            ? true
            : defaults.bool(forKey: autoOrganizeEnabled)
    }
}
