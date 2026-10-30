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
    @Namespace private var ns
    @GestureState private var pressed = false

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
        .shadow(color: .black.opacity(open ? 0.4 : 0), radius: open ? 14 : 0, y: open ? 5 : 0)
        // iPhone-like "squish" when the closed island is pressed.
        .scaleEffect(pressed && !open ? 0.94 : 1, anchor: .top)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
        .opacity(model.idleHidden ? 0 : 1)
        .contentShape(shape)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true }
        )
        .onTapGesture {
            if !model.isOpen { model.open() }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $model.isDropTargeted) { providers in
            model.handleDrop(providers)
        }
        .animation(open ? IslandModel.spring : IslandModel.closeSpring, value: size)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if model.isOpen {
            if model.isDraggingFile || model.isDropTargeted {
                DropZoneView(model: model)
                    .transition(.islandExpanded)
            } else {
                ExpandedView(model: model, player: player, timer: timer, ns: ns)
                    .transition(.islandExpanded)
            }
        } else if let t = model.transient {
            CompactRow(model: model, side: IslandModel.transientSide) {
                TransientLeading(kind: t)
                    .transition(.islandCompact(edge: .leading))
            } trailing: {
                TransientTrailing(kind: t)
                    .transition(.islandCompact(edge: .trailing))
            }
            .id(t.groupID)
        } else if timer.isActive {
            CompactRow(model: model, side: model.compactSide) {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, options: .repeating, isActive: !timer.isRunning)
                    .transition(.islandCompact(edge: .leading))
            } trailing: {
                Text(timer.display)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: timer.display)
                    .transition(.islandCompact(edge: .trailing))
            }
        } else if model.showsMusicCompact {
            CompactRow(model: model, side: model.compactSide) {
                ArtworkView(image: player.artwork, size: model.notchSize.height - 10, radius: 6)
                    .matchedGeometryEffect(id: "artwork", in: ns)
                    .transition(.islandCompact(edge: .leading))
            } trailing: {
                Waveform(color: player.accent, playing: player.isPlaying)
                    .frame(width: 18, height: 14)
                    .matchedGeometryEffect(id: "waveform", in: ns)
                    .transition(.islandCompact(edge: .trailing))
            }
        }
    }
}

// MARK: - Transitions (blur + scale, like the iPhone Dynamic Island)

struct BlurScaleFade: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double
    let anchor: UnitPoint
    var offsetX: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: anchor)
            .offset(x: offsetX)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Content of the open island: blooms out of the notch, blurs away on close.
    static var islandExpanded: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurScaleFade(blur: 12, scale: 0.86, opacity: 0, anchor: .top),
                identity: BlurScaleFade(blur: 0, scale: 1, opacity: 1, anchor: .top)
            ).animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.03)),
            removal: .modifier(
                active: BlurScaleFade(blur: 8, scale: 0.92, opacity: 0, anchor: .top),
                identity: BlurScaleFade(blur: 0, scale: 1, opacity: 1, anchor: .top)
            ).animation(.easeIn(duration: 0.14))
        )
    }

    /// Leading / trailing items of the closed island slide out from behind the notch.
    static func islandCompact(edge: HorizontalEdge) -> AnyTransition {
        let dx: CGFloat = edge == .leading ? 14 : -14
        return .asymmetric(
            insertion: .modifier(
                active: BlurScaleFade(blur: 6, scale: 0.6, opacity: 0, anchor: .center, offsetX: dx),
                identity: BlurScaleFade(blur: 0, scale: 1, opacity: 1, anchor: .center)
            ).animation(.spring(response: 0.38, dampingFraction: 0.8).delay(0.05)),
            removal: .modifier(
                active: BlurScaleFade(blur: 6, scale: 0.7, opacity: 0, anchor: .center, offsetX: dx),
                identity: BlurScaleFade(blur: 0, scale: 1, opacity: 1, anchor: .center)
            ).animation(.easeIn(duration: 0.12))
        )
    }
}

extension AnyTransition {
    static var pageSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurScaleFade(blur: 8, scale: 0.94, opacity: 0, anchor: .center),
                identity: BlurScaleFade(blur: 0, scale: 1, opacity: 1, anchor: .center)
            ).animation(.spring(response: 0.36, dampingFraction: 0.86)),
            removal: .modifier(
                active: BlurScaleFade(blur: 8, scale: 1.04, opacity: 0, anchor: .center),
                identity: BlurScaleFade(blur: 0, scale: 1, opacity: 1, anchor: .center)
            ).animation(.easeIn(duration: 0.12))
        )
    }
}

extension TransientKind {
    /// Same group = same view identity, so repeated volume presses update in place.
    var groupID: String {
        switch self {
        case .charging: return "charging"
        case .volume: return "volume"
        case .brightness: return "brightness"
        case .headphones: return "headphones"
        case .timerDone: return "timerDone"
        case .lowBattery: return "lowBattery"
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
    @State private var appeared = 0

    var body: some View {
        Group {
            switch kind {
            case .charging:
                Text("Charging")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            case let .volume(level, muted):
                Image(systemName: muted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill",
                      variableValue: Double(level))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            case let .brightness(level):
                Image(systemName: "sun.max.fill", variableValue: Double(level))
                    .foregroundStyle(.white)
            case let .headphones(symbol, _, connected):
                Image(systemName: symbol)
                    .foregroundStyle(connected ? Color.white : Color.gray)
                    .symbolEffect(.bounce, value: appeared)
            case .timerDone:
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, options: .repeat(3), value: appeared)
            case .lowBattery:
                Text("Low Battery")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { appeared += 1 }
        }
    }
}

struct TransientTrailing: View {
    let kind: TransientKind

    var body: some View {
        switch kind {
        case let .charging(level, _):
            HStack(spacing: 4) {
                Text("\(level)%").font(.system(size: 12, weight: .semibold).monospacedDigit())
                BatteryGlyph(level: level, color: .green, charging: true)
            }
            .foregroundStyle(.green)
        case let .volume(level, muted):
            LevelBar(value: muted ? 0 : Double(level))
        case let .brightness(level):
            LevelBar(value: Double(level))
        case let .headphones(_, battery, connected):
            if connected, let battery {
                BatteryRing(level: battery)
            } else {
                Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(connected ? Color.green : Color.gray)
            }
        case .timerDone:
            Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        case let .lowBattery(level):
            HStack(spacing: 4) {
                Text("\(level)%").font(.system(size: 12, weight: .semibold).monospacedDigit())
                BatteryGlyph(level: level, color: .red, charging: false)
            }
            .foregroundStyle(.red)
        }
    }
}

/// iOS-style battery: outlined body whose fill grows in with a spring.
struct BatteryGlyph: View {
    let level: Int
    let color: Color
    let charging: Bool
    @State private var shown: CGFloat = 0

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, 19 * shown))
                    .padding(1.5)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 22, height: 11)
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.35)).frame(width: 1.5, height: 4)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.15)) {
                shown = CGFloat(max(0, min(100, level))) / 100
            }
        }
    }
}

/// AirPods-style battery ring that fills in on appear.
struct BatteryRing: View {
    let level: Int
    @State private var shown: CGFloat = 0

    var body: some View {
        let color: Color = level <= 20 ? .red : .green
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 17, height: 17)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.15)) {
                shown = CGFloat(max(0, min(100, level))) / 100
            }
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
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: value)
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var player: NowPlayingService
    @ObservedObject var timer: TimerModel
    let ns: Namespace.ID
    @Namespace private var tabNS

    var body: some View {
        VStack(spacing: 0) {
            // Top row sits beside the physical notch.
            HStack(spacing: 6) {
                TabIcon(symbol: "music.note", selected: model.page == .music, ns: tabNS) { select(.music) }
                TabIcon(symbol: "timer", selected: model.page == .timer, ns: tabNS) { select(.timer) }
                Spacer()
                TabIcon(symbol: "gearshape.fill", selected: false, ns: tabNS) { model.openSettings?() }
            }
            .padding(.horizontal, 26)
            .frame(height: model.notchSize.height)

            Group {
                switch model.page {
                case .music:
                    MusicCard(player: player, ns: ns)
                        .transition(.pageSwap)
                case .timer:
                    TimerCard(timer: timer)
                        .transition(.pageSwap)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
    private func select(_ page: IslandPage) {
        guard model.page != page else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { model.page = page }
    }
}

struct TabIcon: View {
    let symbol: String
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(hover ? 0.75 : 0.4))
                .frame(width: 24, height: 20)
                .background {
                    if selected {
                        Capsule().fill(Color.white.opacity(0.16))
                            .matchedGeometryEffect(id: "tabPill", in: ns)
                    }
                }
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
    let ns: Namespace.ID
    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(image: player.artwork, size: 54, radius: 12)
                    .matchedGeometryEffect(id: "artwork", in: ns)
                    .scaleEffect(player.isPlaying || !player.hasTrack ? 1 : 0.9)
                    .shadow(color: player.accent.opacity(player.isPlaying ? 0.35 : 0), radius: 10)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: player.isPlaying)
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
                    .matchedGeometryEffect(id: "waveform", in: ns)
                    .opacity(player.hasTrack ? 1 : 0)
            }

            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
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
    @State private var taps = 0
    @State private var hover = false

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size + 18, height: size + 12)
                .background(Circle().fill(Color.white.opacity(hover ? 0.1 : 0)))
                .contentTransition(.symbolEffect(.replace.downUp))
                .symbolEffect(.bounce, value: taps)
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
