// STIX Island — GPL-3.0. Based in part on Atoll (Ebullioscopic) and boring.notch.
import AppKit

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
