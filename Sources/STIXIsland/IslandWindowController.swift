import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the transparent panel at the top of the screen and decides when the
/// island should open, close and receive mouse events.
final class IslandWindowController {
    let model: IslandModel
    private let panel: IslandPanel
    private let windowSize = CGSize(width: 680, height: 340)
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var observer: NSObjectProtocol?

    init(model: IslandModel) {
        self.model = model
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: windowSize))
        let host = FirstMouseHostingView(rootView: IslandRootView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView = host
        reposition()
        panel.orderFrontRegardless()
        installMonitors()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reposition()
        }
    }

    // MARK: Placement

    private func targetScreen() -> NSScreen? {
        let builtIn = NSScreen.screens.first { s in
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return CGDisplayIsBuiltin(id) != 0
        }
        return builtIn ?? NSScreen.main ?? NSScreen.screens.first
    }

    func reposition() {
        guard let s = targetScreen() else { return }
        screen = s
        let top = s.safeAreaInsets.top
        if top > 0, let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea {
            model.notchSize = CGSize(width: s.frame.width - left.width - right.width, height: top)
            model.hasNotch = true
        } else {
            let menuBar = s.frame.maxY - s.visibleFrame.maxY
            model.notchSize = CGSize(width: 190, height: max(menuBar, 26))
            model.hasNotch = false
        }
        let frame = NSRect(
            x: s.frame.midX - windowSize.width / 2,
            y: s.frame.maxY - windowSize.height,
            width: windowSize.width, height: windowSize.height)
        panel.setFrame(frame, display: true)
    }

    private func islandRect() -> NSRect {
        guard let s = screen else { return .zero }
        let size = model.currentSize
        return NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    // MARK: Mouse

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] e in
            self?.mouseMoved(e)
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] e in
            self?.mouseMoved(e)
            return e
        }) { monitors.append(m) }

        let downUp: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: downUp, handler: { [weak self] e in
            self?.mouseButton(e)
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: downUp, handler: { [weak self] e in
            self?.mouseButton(e)
            return e
        }) { monitors.append(m) }
    }

    private func mouseButton(_ e: NSEvent) {
        if e.type == .leftMouseDown {
            dragChangeCount = NSPasteboard(name: .drag).changeCount
        } else if model.isDraggingFile {
            // Give a drop on the island time to land before resetting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.model.isDraggingFile = false
                self.update(mouse: NSEvent.mouseLocation)
            }
        }
    }

    private func mouseMoved(_ e: NSEvent) {
        if e.type == .leftMouseDragged, !model.isDraggingFile {
            let pb = NSPasteboard(name: .drag)
            if pb.changeCount != dragChangeCount,
               pb.types?.contains(.fileURL) == true {
                model.isDraggingFile = true
            }
        }
        update(mouse: NSEvent.mouseLocation)
    }

    private func contains(_ rect: NSRect, _ p: NSPoint) -> Bool {
        p.x >= rect.minX && p.x <= rect.maxX && p.y >= rect.minY && p.y <= rect.maxY + 2
    }

    private func update(mouse p: NSPoint) {
        var rect = islandRect()
        if model.isDraggingFile && !model.isOpen {
            rect = rect.insetBy(dx: -40, dy: -30)
        } else if !model.isOpen {
            rect = rect.insetBy(dx: -6, dy: -4)
        }
        let inside = contains(rect, p)
        panel.ignoresMouseEvents = !inside

        if inside {
            closeWork?.cancel()
            closeWork = nil
            guard !model.isOpen, openWork == nil else { return }
            if model.isDraggingFile {
                model.open()
            } else if Prefs.openOnHover {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.openWork = nil
                    if self.contains(self.islandRect().insetBy(dx: -6, dy: -4), NSEvent.mouseLocation) {
                        self.model.open()
                    }
                }
                openWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            }
        } else {
            openWork?.cancel()
            openWork = nil
            guard model.isOpen, closeWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.closeWork = nil
                if !self.contains(self.islandRect(), NSEvent.mouseLocation) {
                    self.model.close()
                    self.panel.ignoresMouseEvents = true
                }
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
}
