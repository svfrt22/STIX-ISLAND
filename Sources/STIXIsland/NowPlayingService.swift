import AppKit
import SwiftUI

/// Reads "Now Playing" info from any player through the bundled
/// mediaremote-adapter (runs under /usr/bin/perl, which macOS 15.4+ still
/// allows to read MediaRemote), and sends commands through MediaRemote.
final class NowPlayingService: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var duration: Double = 0
    @Published private(set) var elapsedAnchor: Double = 0
    @Published private(set) var anchorDate = Date()
    @Published private(set) var rate: Double = 1
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white

    var hasTrack: Bool { !title.isEmpty }

    private var process: Process?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "stix.nowplaying")
    private var lastArtworkKey: Int?
    private var stopped = false

    // MediaRemote command functions
    private typealias SendCommandFn = @convention(c) (Int, AnyObject?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void
    private var sendCommandFn: SendCommandFn?
    private var setElapsedFn: SetElapsedFn?

    init() {
        let url = NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        if let bundle = CFBundleCreate(kCFAllocatorDefault, url) {
            if let p = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
                sendCommandFn = unsafeBitCast(p, to: SendCommandFn.self)
            }
            if let p = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) {
                setElapsedFn = unsafeBitCast(p, to: SetElapsedFn.self)
            }
        }
    }

    // MARK: Stream

    func start() {
        guard process == nil,
              let script = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl"),
              let resources = Bundle.main.resourcePath
        else {
            NSLog("STIX: mediaremote-adapter not found in bundle")
            return
        }
        let framework = resources + "/MediaRemoteAdapter.framework"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script, framework, "stream", "--no-diff", "--micros", "--debounce=60"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let self, !self.stopped else { return }
                self.process = nil
                self.start()
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            NSLog("STIX: failed to start adapter: \(error)")
        }
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            let payload = obj["payload"] as? [String: Any] ?? [:]
            parse(payload)
        }
    }

    private func number(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue
    }

    private func parse(_ p: [String: Any]) {
        let title = p["title"] as? String ?? ""
        let artist = p["artist"] as? String ?? ""
        let duration = number(p["durationMicros"]).map { $0 / 1_000_000 } ?? number(p["duration"]) ?? 0
        let elapsed = number(p["elapsedTimeMicros"]).map { $0 / 1_000_000 } ?? number(p["elapsedTime"]) ?? 0
        let stamp = number(p["timestampEpochMicros"]).map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date()
        let playing = (p["playing"] as? NSNumber)?.boolValue ?? false
        var rate = number(p["playbackRate"]) ?? 1
        if rate <= 0 { rate = 1 }

        // Artwork: decode only when it changes.
        let artString = p["artworkData"] as? String
        let artKey = artString?.hashValue
        var newArtwork: NSImage?? = nil
        var newAccent: Color?
        if artKey != lastArtworkKey {
            lastArtworkKey = artKey
            if let artString,
               let data = Data(base64Encoded: artString.trimmingCharacters(in: .whitespacesAndNewlines)),
               let img = NSImage(data: data) {
                newArtwork = .some(img)
                newAccent = Color(nsColor: Self.accentColor(of: img))
            } else {
                newArtwork = .some(nil)
                newAccent = .white
            }
        }

        let artworkUpdate = newArtwork
        let accentUpdate = newAccent
        let finalRate = rate
        DispatchQueue.main.async {
            let newArtwork = artworkUpdate
            let newAccent = accentUpdate
            let rate = finalRate
            self.title = title
            self.artist = artist
            self.duration = duration
            self.elapsedAnchor = elapsed
            self.anchorDate = stamp
            self.rate = rate
            self.isPlaying = playing && !title.isEmpty
            if let newArtwork { self.artwork = newArtwork }
            if let newAccent { self.accent = newAccent }
        }
    }

    // MARK: Time

    func elapsed(at date: Date) -> Double {
        var t = elapsedAnchor
        if isPlaying { t += date.timeIntervalSince(anchorDate) * rate }
        if duration > 0 { t = min(t, duration) }
        return max(0, t)
    }

    // MARK: Commands

    private func send(_ command: Int) {
        _ = sendCommandFn?(command, nil)
    }

    func togglePlay() {
        // Freeze/unfreeze the clock locally for instant feedback.
        let now = Date()
        elapsedAnchor = elapsed(at: now)
        anchorDate = now
        isPlaying.toggle()
        send(2)
    }

    func next() { send(4) }
    func previous() { send(5) }

    func seek(toFraction f: Double) {
        guard duration > 0 else { return }
        let t = max(0, min(1, f)) * duration
        elapsedAnchor = t
        anchorDate = Date()
        setElapsedFn?(t)
    }

    // MARK: Accent color

    static func accentColor(of image: NSImage) -> NSColor {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        var px = [UInt8](repeating: 0, count: 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return .white }
        let c = NSColor(
            srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1
        )
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.15 { return NSColor(white: 0.92, alpha: 1) }
        return NSColor(hue: h, saturation: min(s, 0.75), brightness: max(b, 0.85), alpha: 1)
    }
}
