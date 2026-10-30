import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics

// MARK: - Volume (CoreAudio)

final class VolumeControl {
    var onChange: ((Float, Bool) -> Void)?

    private var device: AudioDeviceID = 0
    private var listener: AudioObjectPropertyListenerBlock?
    private var lastReport: (Float, Bool)?
    /// Cached so the event-tap callback never touches CoreAudio.
    private(set) var cachedCanSet = true

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return st == noErr && id != 0 ? id : nil
    }

    func start() {
        attach()
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
            self?.attach()
        }
    }

    private func attach() {
        if device != 0, let listener {
            var v = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var m = Self.address(kAudioDevicePropertyMute)
            AudioObjectRemovePropertyListenerBlock(device, &v, DispatchQueue.main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &m, DispatchQueue.main, listener)
        }
        guard let dev = Self.defaultDevice() else { return }
        device = dev
        lastReport = current()
        cachedCanSet = canSet
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, let now = self.current() else { return }
            if let last = self.lastReport, abs(last.0 - now.0) < 0.001, last.1 == now.1 { return }
            self.lastReport = now
            self.onChange?(now.0, now.1)
        }
        listener = block
        var v = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var m = Self.address(kAudioDevicePropertyMute)
        AudioObjectAddPropertyListenerBlock(dev, &v, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(dev, &m, DispatchQueue.main, block)
    }

    var canSet: Bool {
        guard let dev = Self.defaultDevice() else { return false }
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(dev, &addr),
              AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr
        else { return false }
        return settable.boolValue
    }

    func current() -> (Float, Bool)? {
        guard let dev = Self.defaultDevice() else { return nil }
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &vol) == noErr else { return nil }
        var muted = UInt32(0)
        var msize = UInt32(MemoryLayout<UInt32>.size)
        var maddr = Self.address(kAudioDevicePropertyMute)
        if AudioObjectHasProperty(dev, &maddr) {
            _ = AudioObjectGetPropertyData(dev, &maddr, 0, nil, &msize, &muted)
        }
        return (vol, muted != 0)
    }

    func setVolume(_ value: Float) {
        guard let dev = Self.defaultDevice() else { return }
        var v = Float32(max(0, min(1, value)))
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        _ = AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        setMuted(v == 0)
    }

    func setMuted(_ muted: Bool) {
        guard let dev = Self.defaultDevice() else { return }
        var m = UInt32(muted ? 1 : 0)
        var addr = Self.address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(dev, &addr) else { return }
        _ = AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }

    /// Returns the new (level, muted).
    @discardableResult
    func step(up: Bool, fine: Bool) -> (Float, Bool) {
        let (vol, muted) = current() ?? (0, false)
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0
        var target = ((vol / step).rounded() + (up ? 1 : -1)) * step
        target = max(0, min(1, target))
        if muted && up {
            setMuted(false)
        }
        setVolume(target)
        return (target, target == 0)
    }

    @discardableResult
    func toggleMute() -> (Float, Bool) {
        let (vol, muted) = current() ?? (0, false)
        setMuted(!muted)
        return (vol, !muted)
    }
}

// MARK: - Brightness (DisplayServices, built-in display)

enum Brightness {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn: GetFn? = {
        guard let h = Brightness.handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetFn.self)
    }()
    private static let setFn: SetFn? = {
        guard let h = Brightness.handle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetFn.self)
    }()

    static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var available: Bool { Brightness.getFn != nil && Brightness.setFn != nil && Brightness.builtInDisplay != nil }

    static func get() -> Float? {
        guard let getFn = Brightness.getFn, let id = Brightness.builtInDisplay else { return nil }
        var v: Float = 0
        return getFn(id, &v) == 0 ? v : nil
    }

    @discardableResult
    static func step(up: Bool, fine: Bool) -> Float? {
        guard let setFn = Brightness.setFn, let id = Brightness.builtInDisplay, let cur = Brightness.get() else { return nil }
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0
        let target = max(0, min(1, ((cur / step).rounded() + (up ? 1 : -1)) * step))
        _ = setFn(id, target)
        return target
    }
}

/// Watches the built-in display brightness so changes made by any means
/// (keys, Control Center, Touch Bar) show up in the island.
final class BrightnessWatcher {
    var onChange: ((Float) -> Void)?
    private var timer: Timer?
    private var last: Float?

    func start() {
        last = Brightness.get()
        let t = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        guard let now = Brightness.get() else { return }
        defer { last = now }
        guard let last else { return }
        // Key presses move in ~6% steps; auto-brightness drifts slowly and is ignored.
        if abs(now - last) >= 0.012 { onChange?(now) }
    }
}

// MARK: - Media key interception (needs Accessibility)

final class MediaKeyService {
    var onVolume: ((Float, Bool) -> Void)?
    var onBrightness: ((Float) -> Void)?
    let volume: VolumeControl

    private var tap: CFMachPort?
    private var retry: Timer?

    private let brightnessAvailable = Brightness.available

    init(volume: VolumeControl) {
        self.volume = volume
    }

    var isActive: Bool { tap != nil }

    func start() {
        tryCreateTap()
        guard tap == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tryCreateTap() }
        RunLoop.main.add(t, forMode: .common)
        retry = t
    }

    private func tryCreateTap() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let svc = Unmanaged<MediaKeyService>.fromOpaque(refcon).takeUnretainedValue()
            return svc.handle(type: type, event: event)
        }
        var created: CFMachPort?
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            if let t = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                                         eventsOfInterest: mask, callback: callback, userInfo: ctx) {
                created = t
                break
            }
        }
        guard let t = created else { return }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        retry?.invalidate()
        retry = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard Prefs.replaceHUD, Prefs.islandEnabled, type.rawValue == 14,
              let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8
        else { return pass }

        let data1 = ns.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let isDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        let fine = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)

        switch keyCode {
        case 0, 1, 7: // sound up, sound down, mute
            guard volume.cachedCanSet else { return pass }
            if isDown {
                DispatchQueue.main.async {
                    let r = keyCode == 7 ? self.volume.toggleMute() : self.volume.step(up: keyCode == 0, fine: fine)
                    self.onVolume?(r.0, r.1)
                }
            }
            return nil
        case 2, 3: // brightness up, down
            guard brightnessAvailable else { return pass }
            if isDown {
                DispatchQueue.main.async {
                    if let v = Brightness.step(up: keyCode == 2, fine: fine) { self.onBrightness?(v) }
                }
            }
            return nil
        default:
            return pass
        }
    }
}

// MARK: - System OSD suppression

/// Pauses Apple's OSDUIHelper (the process that draws the volume/brightness
/// bezel) so only the island shows those changes. Resumed on quit or when the
/// feature is turned off.
final class OSDSuppressor {
    private let queue = DispatchQueue(label: "stix.osd")
    private var timer: DispatchSourceTimer?
    private var stoppedPID: pid_t?
    private(set) var active = false

    func setActive(_ on: Bool) {
        queue.async {
            guard on != self.active else { return }
            self.active = on
            if on {
                self.ensureStopped(launchIfNeeded: true)
                let t = DispatchSource.makeTimerSource(queue: self.queue)
                t.schedule(deadline: .now() + 2, repeating: 2)
                t.setEventHandler { [weak self] in self?.ensureStopped(launchIfNeeded: false) }
                t.resume()
                self.timer = t
            } else {
                self.timer?.cancel()
                self.timer = nil
                self.resumeAll()
            }
        }
    }

    /// Synchronous resume used on app termination.
    func resumeNow() {
        queue.sync {
            self.active = false
            self.timer?.cancel()
            self.timer = nil
            self.resumeAll()
        }
    }

    private func ensureStopped(launchIfNeeded: Bool) {
        guard active else { return }
        var pid = Self.helperPID()
        if pid == nil && launchIfNeeded {
            Self.run("/bin/launchctl", ["kickstart", "gui/\(getuid())/com.apple.OSDUIHelper"])
            for _ in 0..<20 where pid == nil {
                usleep(150_000)
                pid = Self.helperPID()
            }
        }
        guard let pid else { return }
        if pid != stoppedPID || !Self.isStopped(pid) {
            kill(pid, SIGSTOP)
            stoppedPID = pid
        }
    }

    private func resumeAll() {
        if let pid = Self.helperPID() { kill(pid, SIGCONT) }
        if let old = stoppedPID { kill(old, SIGCONT) }
        stoppedPID = nil
    }

    private static func helperPID() -> pid_t? {
        let out = run("/usr/bin/pgrep", ["-x", "OSDUIHelper"])
        return out.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }.first
    }

    private static func isStopped(_ pid: pid_t) -> Bool {
        run("/bin/ps", ["-o", "state=", "-p", "\(pid)"]).hasPrefix("T")
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
