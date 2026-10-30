import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = NowPlayingService()
    private let timer = TimerModel()
    private lazy var model = IslandModel(player: player, timer: timer)
    private var windowController: IslandWindowController?
    private let settings = SettingsWindowController()
    private let battery = BatteryService()
    private let volume = VolumeControl()
    private lazy var mediaKeys = MediaKeyService(volume: volume)
    private let bluetooth = BluetoothService()
    private let brightnessWatcher = BrightnessWatcher()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()

        model.openSettings = { [weak self] in self?.settings.show() }
        windowController = IslandWindowController(model: model)

        player.start()

        timer.onFinish = { [weak self] in
            NSSound(named: NSSound.Name("Glass"))?.play()
            self?.model.showTransient(.timerDone, duration: 6)
        }

        battery.onPluggedIn = { [weak self] level, charging in
            guard Prefs.showCharging else { return }
            self?.model.showTransient(.charging(level: level, charging: charging), duration: 2.8)
        }
        battery.onLow = { [weak self] level in
            self?.model.showTransient(.lowBattery(level: level), duration: 4)
        }
        battery.start()

        brightnessWatcher.onChange = { [weak self] level in
            guard Prefs.replaceHUD else { return }
            self?.model.showTransient(.brightness(level: level))
        }
        brightnessWatcher.start()

        volume.onChange = { [weak self] level, muted in
            guard Prefs.replaceHUD else { return }
            self?.model.showTransient(.volume(level: level, muted: muted))
        }
        volume.start()

        mediaKeys.onVolume = { [weak self] level, muted in
            self?.model.showTransient(.volume(level: level, muted: muted))
        }
        mediaKeys.onBrightness = { [weak self] level in
            self?.model.showTransient(.brightness(level: level))
        }
        mediaKeys.start()

        bluetooth.onEvent = { [weak self] symbol, batteryLevel, connected in
            guard Prefs.showHeadphones else { return }
            self?.model.showTransient(.headphones(symbol: symbol, battery: batteryLevel, connected: connected),
                                      duration: 3)
        }
        bluetooth.start()

        setupStatusItem()

        if !UserDefaults.standard.bool(forKey: PrefKey.didOnboard) {
            UserDefaults.standard.set(true, forKey: PrefKey.didOnboard)
            settings.show()
            if !AXIsProcessTrusted() { SettingsView.requestAccessibility() }
        }
    }

    /// Launching the app again (Finder, Launchpad, Spotlight) opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        player.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "STIX Island")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit STIX Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        settings.show()
    }
}
