import AppKit

final class TimerModel: ObservableObject {
    @Published private(set) var duration: TimeInterval = 5 * 60
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var tick = Date()

    var onFinish: (() -> Void)?
    private var ticker: Timer?

    var isRunning: Bool { endDate != nil }
    var isActive: Bool { endDate != nil || pausedRemaining != nil }

    var remaining: TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSinceNow) }
        return pausedRemaining ?? duration
    }

    var display: String {
        let total = Int(remaining.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    func setMinutes(_ minutes: Int) {
        guard !isActive else { return }
        duration = TimeInterval(minutes * 60)
    }

    func adjust(by seconds: TimeInterval) {
        if let endDate {
            self.endDate = max(Date().addingTimeInterval(1), endDate.addingTimeInterval(seconds))
        } else if let pausedRemaining {
            self.pausedRemaining = max(1, pausedRemaining + seconds)
        } else {
            duration = min(max(60, duration + seconds), 24 * 3600)
        }
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        endDate = Date().addingTimeInterval(pausedRemaining ?? duration)
        pausedRemaining = nil
        startTicker()
    }

    func pause() {
        pausedRemaining = remaining
        endDate = nil
        stopTicker()
    }

    func reset() {
        endDate = nil
        pausedRemaining = nil
        stopTicker()
    }

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick = Date()
            if let end = self.endDate, end.timeIntervalSinceNow <= 0 {
                self.reset()
                self.onFinish?()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
