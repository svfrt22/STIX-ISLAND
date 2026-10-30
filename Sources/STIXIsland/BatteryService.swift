import Foundation
import IOKit.ps

final class BatteryService {
    /// level (0-100), isCharging
    var onPluggedIn: ((Int, Bool) -> Void)?

    private var source: CFRunLoopSource?
    private var lastOnAC: Bool?

    struct Reading {
        let level: Int
        let charging: Bool
        let onAC: Bool
    }

    func start() {
        lastOnAC = Self.read()?.onAC
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let svc = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            svc.update()
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, ctx)?.takeRetainedValue() {
            source = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private func update() {
        guard let r = Self.read() else { return }
        if r.onAC, lastOnAC == false {
            onPluggedIn?(r.level, r.charging)
        }
        lastOnAC = r.onAC
    }

    static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as NSArray?
        else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps as AnyObject)?.takeUnretainedValue()
                    as? [String: Any]
            else { continue }
            guard (desc["Type"] as? String) == "InternalBattery" else { continue }
            let cur = (desc["Current Capacity"] as? NSNumber)?.intValue ?? 0
            let maxCap = (desc["Max Capacity"] as? NSNumber)?.intValue ?? 100
            let charging = (desc["Is Charging"] as? NSNumber)?.boolValue ?? false
            let onAC = (desc["Power Source State"] as? String) == "AC Power"
            let level = maxCap > 0 ? Int((Double(cur) / Double(maxCap) * 100).rounded()) : cur
            return Reading(level: level, charging: charging, onAC: onAC)
        }
        return nil
    }
}
