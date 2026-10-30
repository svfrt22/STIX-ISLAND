import AppKit
import ServiceManagement
import SwiftUI

enum Permissions {
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

// MARK: - Window

final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = .black
            w.isReleasedWhenClosed = false
            w.title = "STIX Island"
            w.contentView = NSHostingView(rootView: MainView())
            w.delegate = self
            w.center()
            window = w
        }
        // Behave like a normal app (Dock icon, Cmd+Tab) while the window is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }
}

// MARK: - Palette

private enum Palette {
    static let bg = Color(red: 0.04, green: 0.04, blue: 0.045)
    static let field = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let stroke = Color.white.opacity(0.07)
    static let secondary = Color.white.opacity(0.5)
    static let tertiary = Color.white.opacity(0.32)
}

// MARK: - Main view

struct MainView: View {
    @AppStorage(PrefKey.islandEnabled) private var enabled = true
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
        ZStack {
            AmbientBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 46)

                    IslandPreview(enabled: enabled)
                        .padding(.top, 26)

                    MasterSwitch(enabled: $enabled)
                        .padding(.top, 18)

                    SectionLabel("LIVE ACTIVITIES").padding(.top, 26)
                    VStack(spacing: 8) {
                        FieldRow(icon: "music.note", title: "Music", subtitle: "Always on") { EmptyView() }
                        FieldRow(icon: "bolt.fill", title: "Charging & low battery") {
                            PillToggle(isOn: $showCharging)
                        }
                        FieldRow(icon: "airpodspro", title: "Headphones") {
                            PillToggle(isOn: $showHeadphones)
                        }
                        FieldRow(icon: "speaker.wave.2.fill", title: "Volume & brightness") {
                            PillToggle(isOn: $replaceHUD)
                        }
                        if replaceHUD && !trusted {
                            AccessNotice()
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)

                    SectionLabel("BEHAVIOUR").padding(.top, 22)
                    VStack(spacing: 8) {
                        FieldRow(icon: "cursorarrow.motionlines", title: "Open island") {
                            Segmented(selection: $openOnHover,
                                      options: [(true, "Hover"), (false, "Click")])
                        }
                        FieldRow(icon: "power", title: "Launch at login") {
                            PillToggle(isOn: $launchAtLogin)
                        }
                    }

                    footer.padding(.top, 26).padding(.bottom, 22)
                }
                .padding(.horizontal, 34)
            }
        }
        .frame(width: 460, height: 760)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: enabled)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: trusted)
        .onReceive(poll) { _ in trusted = AXIsProcessTrusted() }
        .onChange(of: launchAtLogin) { _, on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 58, height: 58)
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.field)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.stroke))
                )
            VStack(spacing: 4) {
                Text("STIX")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                Text("ISLAND")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Palette.secondary)
            }
            Text("Your notch, reimagined.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle().fill(Palette.stroke).frame(height: 1)
            HStack {
                Link("stixart.shop", destination: URL(string: "https://stixart.shop")!)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Text("·  v\(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}

// MARK: - Components

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Palette.bg
            Circle().fill(Color.white.opacity(0.13)).frame(width: 340).blur(radius: 110)
                .offset(x: 200, y: -330)
            Circle().fill(Color.white.opacity(0.09)).frame(width: 320).blur(radius: 110)
                .offset(x: -210, y: 360)
            Ellipse().fill(Color(red: 1, green: 0.45, blue: 0.15).opacity(0.10)).frame(width: 300, height: 160)
                .blur(radius: 70)
                .offset(y: -90)
        }
        .ignoresSafeArea()
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Palette.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }
}

struct FieldRow<Accessory: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            accessory
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Palette.field.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.stroke))
        )
    }
}

struct PillToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Color.white : Color.white.opacity(0.12))
                Circle()
                    .fill(isOn ? Color.black : Color.white.opacity(0.75))
                    .padding(3)
            }
            .frame(width: 38, height: 22)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

struct Segmented: View {
    @Binding var selection: Bool
    let options: [(Bool, String)]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let label = options[i].1
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == value ? Color.black : Color.white.opacity(0.7))
                        .frame(width: 54, height: 24)
                        .background {
                            if selection == value {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

struct MasterSwitch: View {
    @Binding var enabled: Bool

    var body: some View {
        Button {
            enabled.toggle()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Island")
                        .font(.system(size: 15, weight: .semibold))
                    Text(enabled ? "On — living in your notch" : "Off")
                        .font(.system(size: 12))
                        .opacity(0.6)
                        .contentTransition(.opacity)
                }
                Spacer()
                ZStack(alignment: enabled ? .trailing : .leading) {
                    Capsule().fill(enabled ? Color.black : Color.white.opacity(0.15))
                    Circle().fill(enabled ? Color.white : Color.white.opacity(0.8)).padding(3)
                }
                .frame(width: 46, height: 26)
            }
            .foregroundStyle(enabled ? Color.black : Color.white)
            .padding(.horizontal, 18)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(enabled ? Color.white : Palette.field)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.stroke))
                    .shadow(color: .white.opacity(enabled ? 0.12 : 0), radius: 18)
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: enabled)
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct AccessNotice: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text("Allow Accessibility so volume and brightness appear in the island.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button {
                Permissions.requestAccessibility()
            } label: {
                Text("Allow")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.orange.opacity(0.25)))
        )
    }
}

/// A small live demo of the island that breathes between compact and expanded.
struct IslandPreview: View {
    let enabled: Bool
    @State private var expanded = false

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.stroke))

            // Mini island
            ZStack(alignment: .top) {
                IslandShape(topRadius: expanded ? 7 : 4, bottomRadius: expanded ? 20 : 9)
                    .fill(Color.black)
                if expanded {
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule().fill(Color.white.opacity(0.9)).frame(width: 74, height: 6)
                            Capsule().fill(Color.white.opacity(0.4)).frame(width: 50, height: 5)
                        }
                        Spacer(minLength: 0)
                        Waveform(color: .orange, playing: enabled).frame(width: 14, height: 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 26)
                    .transition(.islandExpanded)
                } else {
                    HStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(width: 14, height: 14)
                        Spacer()
                        Waveform(color: .orange, playing: enabled).frame(width: 12, height: 10)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 22)
                    .transition(.opacity)
                }
            }
            .frame(width: expanded ? 230 : 150, height: expanded ? 86 : 22)
            .clipShape(IslandShape(topRadius: expanded ? 7 : 4, bottomRadius: expanded ? 20 : 9))
            .shadow(color: .black.opacity(0.5), radius: expanded ? 12 : 0, y: 4)
            .opacity(enabled ? 1 : 0.25)
            .padding(.top, 1)
        }
        .frame(height: 130)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                guard enabled else { continue }
                withAnimation(expanded ? IslandModel.closeSpring : IslandModel.spring) { expanded.toggle() }
            }
        }
    }
}
