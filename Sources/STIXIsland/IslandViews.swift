import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shape

/// Flat top that blends into the screen edge, soft inverted "ears" at the top
/// corners and large rounded bottom corners.
struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let tr = topRadius
        let br = min(bottomRadius, rect.height / 2, (rect.width - tr * 2) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Root

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            IslandView(model: model, player: model.player, timer: model.timer)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var player: NowPlayingService
    @ObservedObject var timer: TimerModel

    var body: some View {
        let size = model.currentSize
        let open = model.isOpen
        let shape = IslandShape(topRadius: open ? 12 : 6, bottomRadius: open ? 34 : 12)

        ZStack(alignment: .top) {
            shape.fill(Color.black)
            content
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 16, y: 6)
        .opacity(model.idleHidden ? 0 : 1)
        .contentShape(shape)
        .onTapGesture {
            if !model.isOpen { model.open() }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $model.isDropTargeted) { providers in
            model.handleDrop(providers)
        }
        .animation(IslandModel.spring, value: size)
        .animation(IslandModel.spring, value: open)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if model.isOpen {
            if model.isDraggingFile || model.isDropTargeted {
                DropZoneView(model: model)
                    .transition(.opacity)
            } else {
                ExpandedView(model: model, player: player, timer: timer)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        } else if let t = model.transient {
            CompactRow(model: model, side: IslandModel.transientSide) {
                TransientLeading(kind: t)
            } trailing: {
                TransientTrailing(kind: t)
            }
            .transition(.opacity)
            .id("transient")
        } else if timer.isActive {
            CompactRow(model: model, side: model.compactSide) {
                Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
            } trailing: {
                Text(timer.display)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .transition(.opacity)
        } else if model.showsMusicCompact {
            CompactRow(model: model, side: model.compactSide) {
                ArtworkView(image: player.artwork, size: model.notchSize.height - 10, radius: 6)
            } trailing: {
                Waveform(color: player.accent, playing: player.isPlaying)
                    .frame(width: 18, height: 14)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Compact

struct CompactRow<Leading: View, Trailing: View>: View {
    @ObservedObject var model: IslandModel
    let side: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: side, alignment: .center)
                .padding(.leading, 6)
            Spacer(minLength: 0)
            trailing
                .frame(width: side, alignment: .center)
                .padding(.trailing, 6)
        }
        .frame(height: model.notchSize.height)
    }
}

struct TransientLeading: View {
    let kind: TransientKind

    var body: some View {
        Group {
            switch kind {
            case .charging:
                Image(systemName: "bolt.fill").foregroundStyle(.green)
            case let .volume(level, muted):
                Image(systemName: Self.speaker(level, muted)).foregroundStyle(.white)
            case .brightness:
                Image(systemName: "sun.max.fill").foregroundStyle(.white)
            case let .headphones(symbol, _, connected):
                Image(systemName: symbol).foregroundStyle(connected ? Color.white : Color.gray)
            case .timerDone:
                Image(systemName: "timer").foregroundStyle(.orange)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .contentTransition(.symbolEffect(.replace))
    }

    static func speaker(_ level: Float, _ muted: Bool) -> String {
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

struct TransientTrailing: View {
    let kind: TransientKind

    var body: some View {
        switch kind {
        case let .charging(level, _):
            HStack(spacing: 4) {
                Text("\(level)%").font(.system(size: 12, weight: .semibold).monospacedDigit())
                Image(systemName: Self.batterySymbol(level)).font(.system(size: 13))
            }
            .foregroundStyle(.green)
        case let .volume(level, muted):
            LevelBar(value: muted ? 0 : Double(level))
        case let .brightness(level):
            LevelBar(value: Double(level))
        case let .headphones(_, battery, connected):
            if connected, let battery {
                HStack(spacing: 3) {
                    Text("\(battery)%").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Image(systemName: Self.batterySymbol(battery)).font(.system(size: 12))
                }
                .foregroundStyle(battery <= 20 ? Color.red : Color.green)
            } else {
                Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(connected ? Color.green : Color.gray)
            }
        case .timerDone:
            Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        }
    }

    static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(Color.white)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(width: 52, height: 5)
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var player: NowPlayingService
    @ObservedObject var timer: TimerModel

    var body: some View {
        VStack(spacing: 0) {
            // Top row sits beside the physical notch.
            HStack(spacing: 6) {
                TabIcon(symbol: "music.note", selected: model.page == .music) { model.page = .music }
                TabIcon(symbol: "timer", selected: model.page == .timer) { model.page = .timer }
                Spacer()
                TabIcon(symbol: "gearshape.fill", selected: false) { model.openSettings?() }
            }
            .padding(.horizontal, 26)
            .frame(height: model.notchSize.height)

            Group {
                switch model.page {
                case .music: MusicCard(player: player)
                case .timer: TimerCard(timer: timer)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

struct TabIcon: View {
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(hover ? 0.75 : 0.4))
                .frame(width: 24, height: 20)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct MusicCard: View {
    @ObservedObject var player: NowPlayingService
    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(image: player.artwork, size: 54, radius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.hasTrack ? player.title : "Nothing playing")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(player.hasTrack ? player.artist : "Play something in any app")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Waveform(color: player.accent, playing: player.isPlaying)
                    .frame(width: 20, height: 16)
                    .opacity(player.hasTrack ? 1 : 0)
            }

            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let elapsed = scrub.map { $0 * player.duration } ?? player.elapsed(at: ctx.date)
                HStack(spacing: 10) {
                    Text(Self.format(elapsed))
                        .frame(width: 38, alignment: .leading)
                    ScrubBar(fraction: player.duration > 0 ? elapsed / player.duration : 0,
                             scrub: $scrub) { f in player.seek(toFraction: f) }
                    Text("-" + Self.format(max(0, player.duration - elapsed)))
                        .frame(width: 42, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }
            .opacity(player.hasTrack ? 1 : 0.35)

            HStack(spacing: 46) {
                ControlButton(symbol: "backward.fill", size: 20) { player.previous() }
                ControlButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 28) {
                    player.togglePlay()
                }
                ControlButton(symbol: "forward.fill", size: 20) { player.next() }
            }
            .disabled(!player.hasTrack)
            .opacity(player.hasTrack ? 1 : 0.35)
        }
    }

    static func format(_ t: Double) -> String {
        guard t.isFinite else { return "0:00" }
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct ScrubBar: View {
    let fraction: Double
    @Binding var scrub: Double?
    let onCommit: (Double) -> Void
    @State private var hover = false

    var body: some View {
        GeometryReader { geo in
            let f = max(0, min(1, scrub ?? fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white.opacity(0.9)).frame(width: f * geo.size.width)
            }
            .frame(height: hover || scrub != nil ? 7 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in scrub = max(0, min(1, v.location.x / geo.size.width)) }
                    .onEnded { v in
                        let value = max(0, min(1, v.location.x / geo.size.width))
                        onCommit(value)
                        scrub = nil
                    }
            )
        }
        .frame(height: 14)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var pressed = false
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size + 18, height: size + 12)
                .background(Circle().fill(Color.white.opacity(hover ? 0.1 : 0)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct Waveform: View {
    let color: Color
    let playing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: geo.size.width * 0.12) {
                    ForEach(0..<4, id: \.self) { i in
                        let phase = t * (2.6 + Double(i) * 1.15) + Double(i) * 1.7
                        let h = playing ? 0.3 + 0.7 * abs(sin(phase)) : 0.22
                        Capsule()
                            .fill(color)
                            .frame(height: max(2, geo.size.height * h))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - Timer

struct TimerCard: View {
    @ObservedObject var timer: TimerModel
    private let presets = [1, 5, 10, 15, 25, 45]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                RoundIcon(symbol: "minus") { timer.adjust(by: -60) }
                Text(timer.display)
                    .font(.system(size: 40, weight: .light).monospacedDigit())
                    .foregroundStyle(timer.isActive ? Color.orange : Color.white)
                    .frame(minWidth: 140)
                    .contentTransition(.numericText(countsDown: true))
                RoundIcon(symbol: "plus") { timer.adjust(by: 60) }
            }

            if timer.isActive {
                HStack(spacing: 12) {
                    PillButton(title: timer.isRunning ? "Pause" : "Resume",
                               tint: .orange) { timer.toggle() }
                    PillButton(title: "Cancel", tint: .white.opacity(0.18)) { timer.reset() }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { m in
                        Button { timer.setMinutes(m) } label: {
                            Text("\(m)m")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 38, height: 22)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                PillButton(title: "Start", tint: .orange) { timer.start() }
            }
        }
    }
}

struct RoundIcon: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct PillButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 28)
                .background(Capsule().fill(tint))
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Drop zone

struct DropZoneView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: model.notchSize.height)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(Color.white.opacity(model.isDropTargeted ? 0.8 : 0.3))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.blue.opacity(model.isDropTargeted ? 0.18 : 0.06))
                )
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("Drop to send with AirDrop")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                )
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .animation(.easeOut(duration: 0.15), value: model.isDropTargeted)
        }
    }
}
