import AppKit
import ServiceManagement
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: host)
            w.title = "STIX Island"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @AppStorage(PrefKey.openOnHover) private var openOnHover = true
    @AppStorage(PrefKey.showCharging) private var showCharging = true
    @AppStorage(PrefKey.showHeadphones) private var showHeadphones = true
    @AppStorage(PrefKey.replaceHUD) private var replaceHUD = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = AXIsProcessTrusted()
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black)
                        Capsule().fill(Color.white).frame(width: 22, height: 8)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STIX Island").font(.system(size: 15, weight: .semibold))
                        Text("Version \(version)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Picker("Open island", selection: $openOnHover) {
                    Text("On hover").tag(true)
                    Text("On click").tag(false)
                }
            }

            Section("Live activities") {
                Toggle("Charging", isOn: $showCharging)
                Toggle("Headphones", isOn: $showHeadphones)
                Toggle("Volume & brightness in the island", isOn: $replaceHUD)
                if replaceHUD && !trusted {
                    HStack {
                        Text("Needs Accessibility access to replace the system indicator.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant Access") { Self.requestAccessibility() }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit STIX Island") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(poll) { _ in trusted = AXIsProcessTrusted() }
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
