import Foundation
import IOBluetooth

/// Notifies when Bluetooth audio devices (AirPods, headphones) connect or disconnect.
final class BluetoothService: NSObject {
    /// symbol, battery %, connected
    var onEvent: ((String, Int?, Bool) -> Void)?

    private var connectNote: IOBluetoothUserNotification?
    private let startDate = Date()

    func start() {
        connectNote = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        _ = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // Skip devices that were already connected when the app launched.
        guard Date().timeIntervalSince(startDate) > 4, Self.isAudio(device) else { return }
        // Battery levels arrive a moment after the connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.onEvent?(Self.symbol(for: device), Self.battery(of: device), true)
        }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        guard Self.isAudio(device) else { return }
        onEvent?(Self.symbol(for: device), nil, false)
    }

    static func isAudio(_ device: IOBluetoothDevice) -> Bool {
        if device.deviceClassMajor == 0x04 { return true } // Audio/Video
        let name = (device.name ?? "").lowercased()
        return name.contains("airpods") || name.contains("beats") || name.contains("headphone")
            || name.contains("buds")
    }

    static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    static func battery(of device: IOBluetoothDevice) -> Int? {
        let keys = ["batteryPercentCombined", "batteryPercentSingle", "batteryPercentLeft", "batteryPercentRight"]
        var values: [Int] = []
        for key in keys where device.responds(to: NSSelectorFromString(key)) {
            if let n = device.value(forKey: key) as? NSNumber, n.intValue > 0, n.intValue <= 100 {
                if key == "batteryPercentCombined" || key == "batteryPercentSingle" { return n.intValue }
                values.append(n.intValue)
            }
        }
        return values.min()
    }
}
