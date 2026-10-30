import Foundation

enum PrefKey {
    static let islandEnabled = "islandEnabled"
    static let openOnHover = "openOnHover"
    static let showCharging = "showCharging"
    static let showHeadphones = "showHeadphones"
    static let replaceHUD = "replaceHUD"
    static let didOnboard = "didOnboard"
}

enum Prefs {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.islandEnabled: true,
            PrefKey.openOnHover: true,
            PrefKey.showCharging: true,
            PrefKey.showHeadphones: true,
            PrefKey.replaceHUD: true,
            PrefKey.didOnboard: false,
        ])
    }

    static var islandEnabled: Bool { UserDefaults.standard.bool(forKey: PrefKey.islandEnabled) }
    static var openOnHover: Bool { UserDefaults.standard.bool(forKey: PrefKey.openOnHover) }
    static var showCharging: Bool { UserDefaults.standard.bool(forKey: PrefKey.showCharging) }
    static var showHeadphones: Bool { UserDefaults.standard.bool(forKey: PrefKey.showHeadphones) }
    static var replaceHUD: Bool { UserDefaults.standard.bool(forKey: PrefKey.replaceHUD) }
}
