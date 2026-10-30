import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum IslandPage {
    case music
    case timer
}

enum TransientKind: Equatable {
    case charging(level: Int, charging: Bool)
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case headphones(symbol: String, battery: Int?, connected: Bool)
    case timerDone
    case lowBattery(level: Int)
}

final class IslandModel: ObservableObject {
    /// Opening: a gentle, Apple-like spring with a hint of bounce.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    /// Closing: critically damped, so nothing wobbles or hangs.
    static let closeSpring = Animation.spring(response: 0.3, dampingFraction: 1.0)

    @Published var isOpen = false
    @Published var page: IslandPage = .music
    @Published var transient: TransientKind?
    @Published var isDraggingFile = false
    @Published var isDropTargeted = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = false

    let player: NowPlayingService
    let timer: TimerModel
    var openSettings: (() -> Void)?

    private var transientWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(player: NowPlayingService, timer: TimerModel) {
        self.player = player
        self.timer = timer
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        timer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: Geometry

    static let transientSide: CGFloat = 78

    var compactSide: CGFloat { notchSize.height + 8 }

    var openSize: CGSize {
        CGSize(width: max(notchSize.width + 200, 430), height: notchSize.height + 152)
    }

    var showsMusicCompact: Bool { player.hasTrack && player.isPlaying }

    var closedSize: CGSize {
        if transient != nil {
            return CGSize(width: notchSize.width + Self.transientSide * 2, height: notchSize.height)
        }
        if timer.isActive || showsMusicCompact {
            return CGSize(width: notchSize.width + compactSide * 2, height: notchSize.height)
        }
        return notchSize
    }

    var currentSize: CGSize { isOpen ? openSize : closedSize }

    /// On Macs without a notch the idle island is invisible.
    var idleHidden: Bool {
        !hasNotch && !isOpen && transient == nil && !timer.isActive && !showsMusicCompact
    }

    // MARK: Open / close

    func open() {
        guard !isOpen else { return }
        if timer.isActive && !showsMusicCompact {
            page = .timer
        } else if player.hasTrack {
            page = .music
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(Self.spring) { isOpen = true }
    }

    func close() {
        guard isOpen else { return }
        withAnimation(Self.closeSpring) { isOpen = false }
    }

    func showTransient(_ kind: TransientKind, duration: TimeInterval = 2.2) {
        transientWork?.cancel()
        if transient != kind {
            withAnimation(Self.spring) { transient = kind }
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(IslandModel.closeSpring) { self?.transient = nil }
        }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: AirDrop

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url { urls.append(url) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isDraggingFile = false
            self?.close()
            guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: urls)
        }
        return true
    }
}
