import Foundation
import IOKit.ps

final class BatteryService {
    /// level (0-100), isCharging
    var onPluggedIn: ((Int, Bool) -> Void)?
    /// Fired once when the battery drops to 20%, 10% and 5% while unplugged.
    var onLow: ((Int) -> Void)?
    private var lastLevel: Int?
    private let lowThresholds = [20, 10, 5]

    private var source: CFRunLoopSource?
    private var lastOnAC: Bool?

    struct Reading {
        let level: Int
        let charging: Bool
        let onAC: Bool
    }

    func start() {
        let first = Self.read()
        lastOnAC = first?.onAC
        lastLevel = first?.level
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
        if !r.onAC, let last = lastLevel,
           let hit = lowThresholds.first(where: { r.level <= $0 && last > $0 }) {
            _ = hit
            onLow?(r.level)
        }
        lastOnAC = r.onAC
        lastLevel = r.level
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
