import AppKit
import Combine
import CoolMenuCore

final class WindowManager {
    static let shared = WindowManager()

    private struct Placement {
        let bindingID: UUID
        let index: Int
        let result: CGRect
    }

    private let store = SettingsStore.shared
    private var cancellables: Set<AnyCancellable> = []
    private var lastPlacement: [CGWindowID: Placement] = [:]
    private var autoLayoutTimer: Timer?
    /// Cheap window-server snapshot per display; nil until the first sample.
    private var lastWindowSets: [CGDirectDisplayID: Set<CGWindowID>]?
    /// The standard windows each display was last tiled with.
    private var lastTiled: [CGDirectDisplayID: Set<CGWindowID>] = [:]

    private var settings: AppSettings { store.settings }

    func start() {
        store.observe(\.windowBindings)
            .sink { [weak self] bindings in self?.register(bindings) }
            .store(in: &cancellables)
        store.observe(\.autoLayoutEnabled)
            .sink { [weak self] enabled in self?.setAutoLayout(enabled) }
            .store(in: &cancellables)
    }

    private func register(_ bindings: [WindowBinding]) {
        HotKeyCenter.shared.unregister(group: "window")
        for binding in bindings {
            HotKeyCenter.shared.register(group: "window", binding.combo) { [weak self] in
                self?.perform(binding)
            }
        }
    }

    func perform(_ binding: WindowBinding) {
        guard AX.ensureTrusted(for: "window snapping") else { return }
        if case .autoLayout = binding.action {
            if let screen = focusedScreen() { autoLayout(screen) }
            return
        }
        guard let window = AX.focusedWindow(), let axFrame = AX.frame(of: window) else { return }
        let frame = Coordinates.toAppKit(axFrame)
        guard let screen = NSScreen.best(for: frame) else { return }

        switch binding.action {
        case .zones(let names):
            cycle(window, frame: frame, screen: screen, names: names, bindingID: binding.id)
        case .nextDisplay:
            move(window, frame: frame, from: screen, offset: 1)
        case .previousDisplay:
            move(window, frame: frame, from: screen, offset: -1)
        case .autoLayout:
            break
        }
    }

    // MARK: Zones

    private func cycle(_ window: AXUIElement, frame: CGRect, screen: NSScreen, names: [String], bindingID: UUID) {
        guard let layout = LayoutPicker.pick(settings.layouts, for: screen.frame.size) else { return }
        let gap = CGFloat(settings.windowGap)
        let candidates = names
            .compactMap { layout.zone(named: $0)?.frame(in: screen.visibleFrame) }
            .map { $0.insetBy(dx: gap / 2, dy: gap / 2) }

        let windowID = AX.windowID(window)
        let last = windowID.flatMap { lastPlacement[$0] }.flatMap { $0.bindingID == bindingID ? $0 : nil }
        guard let index = ZoneCycler.nextIndex(
            current: frame, candidates: candidates, lastIndex: last?.index, lastResult: last?.result
        ) else { return }

        AX.setFrame(window, Coordinates.toAX(candidates[index]))
        if let windowID, let result = AX.frame(of: window) {
            lastPlacement[windowID] = Placement(bindingID: bindingID, index: index, result: Coordinates.toAppKit(result))
        }
    }

    // MARK: Displays

    private func move(_ window: AXUIElement, frame: CGRect, from screen: NSScreen, offset: Int) {
        // Left-to-right order so "next" means the display to the right.
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard screens.count > 1, let i = screens.firstIndex(of: screen) else { return }
        let target = screens[(i + offset + screens.count) % screens.count]
        let mapped = ScreenCoordinates.remap(frame, from: screen.visibleFrame, to: target.visibleFrame)
        AX.setFrame(window, Coordinates.toAX(mapped))
    }

    // MARK: Auto-layout

    private func focusedScreen() -> NSScreen? {
        if let window = AX.focusedWindow(), let frame = AX.frame(of: window) {
            return NSScreen.best(for: Coordinates.toAppKit(frame))
        }
        return NSScreen.withMouse()
    }

    /// Tiles every standard, visible window on `screen` into a grid, front-most first.
    func autoLayout(_ screen: NSScreen) {
        guard AX.ensureTrusted(for: "auto-layout") else { return }
        let windows = tileableWindows(on: screen)
        let frames = GridLayout.frames(count: windows.count, in: screen.visibleFrame, gap: CGFloat(settings.autoLayoutGap))
        for (window, frame) in zip(windows, frames) {
            AX.setFrame(window, Coordinates.toAX(frame))
        }
        if let display = screen.displayID {
            lastTiled[display] = Set(windows.compactMap(AX.windowID))
        }
    }

    private func tileableWindows(on screen: NSScreen) -> [AXUIElement] {
        let order = Self.zOrder()
        var windows: [(element: AXUIElement, rank: Int)] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            for window in AX.windows(of: app.processIdentifier) {
                guard AX.isStandardWindow(window),
                      !AX.bool(window, kAXMinimizedAttribute),
                      !AX.bool(window, "AXFullScreen"),
                      let frame = AX.frame(of: window),
                      NSScreen.best(for: Coordinates.toAppKit(frame)) == screen
                else { continue }
                let rank = AX.windowID(window).flatMap { order[$0] } ?? Int.max
                windows.append((window, rank))
            }
        }
        return windows.sorted { $0.rank < $1.rank }.map(\.element)
    }

    /// Front-to-back rank of on-screen windows. Needs no permission (titles are not read).
    static func zOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [:] }
        var order: [CGWindowID: Int] = [:]
        for (rank, info) in list.enumerated() where (info[kCGWindowLayer as String] as? Int) == 0 {
            if let id = info[kCGWindowNumber as String] as? CGWindowID { order[id] = rank }
        }
        return order
    }

    /// When enabled, re-tiles a display whenever a window opens or closes on it. Polls the
    /// window server (cheap, permission-free) rather than wiring an AXObserver into every app.
    private func setAutoLayout(_ enabled: Bool) {
        autoLayoutTimer?.invalidate()
        autoLayoutTimer = nil
        lastWindowSets = nil
        lastTiled = [:]
        guard enabled else { return }
        autoLayoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkWindowSets()
        }
    }

    private func checkWindowSets() {
        guard AX.isTrusted,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return }
        let regularPids = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .map(\.processIdentifier))

        var sets: [CGDirectDisplayID: Set<CGWindowID>] = [:]
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, regularPids.contains(pid),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 120, bounds.height > 120,
                  let display = NSScreen.best(for: Coordinates.toAppKit(bounds))?.displayID
            else { continue }
            sets[display, default: []].insert(id)
        }

        defer { lastWindowSets = sets }
        guard let previous = lastWindowSets else { return }
        for screen in NSScreen.screens {
            guard let display = screen.displayID, sets[display, default: []] != previous[display, default: []] else { continue }
            // The window-server set also moves for sheets, popovers and Space switches; only
            // re-tile when the standard windows themselves changed.
            let standard = Set(tileableWindows(on: screen).compactMap(AX.windowID))
            if standard != lastTiled[display, default: []] { autoLayout(screen) }
        }
    }
}
