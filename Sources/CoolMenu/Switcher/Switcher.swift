import AppKit
import Combine
import CoolMenuCore
import SwiftUI

struct SwitcherWindow: Identifiable {
    let id: String
    let element: AXUIElement
    let app: NSRunningApplication
    let title: String
    let minimized: Bool

    var appName: String { app.localizedName ?? "" }
}

/// Alt-Tab over every window of every app. Hold the shortcut's modifier and tap the key to step,
/// release to switch; a quick tap jumps to the previous window. The search shortcut opens it
/// sticky with the search field focused.
final class SwitcherController: ObservableObject {
    static let shared = SwitcherController()

    @Published var query = ""
    @Published var selection = 0
    @Published private(set) var windows: [SwitcherWindow] = []
    @Published private(set) var searchMode = false

    private var holdModifiers: NSEvent.ModifierFlags = []
    /// Backstop for release detection: flagsChanged only reaches the panel if it became key.
    private var releaseTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private lazy var panel = FloatingPanel(size: NSSize(width: 560, height: 420)) {
        SwitcherView(controller: self)
    }

    var results: [SwitcherWindow] {
        guard !query.isEmpty else { return windows }
        return windows
            .compactMap { w -> (SwitcherWindow, Int)? in
                let score = max(FuzzyMatch.score(query, in: w.title) ?? -1, FuzzyMatch.score(query, in: w.appName) ?? -1)
                return score >= 0 ? (w, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    func start() {
        let store = SettingsStore.shared
        Publishers.CombineLatest3(store.observe(\.switcherEnabled), store.observe(\.switcherHotKey), store.observe(\.switcherSearchHotKey))
            .sink { enabled, combo, searchCombo in
                let center = HotKeyCenter.shared
                center.unregister(group: "switcher")
                guard enabled else { return }
                center.register(group: "switcher", combo) { SwitcherController.shared.step(by: 1, combo: combo) }
                if let reverse = HotKeyConflicts.switcherReverse(of: combo) {
                    center.register(group: "switcher", reverse) { SwitcherController.shared.step(by: -1, combo: combo) }
                }
                center.register(group: "switcher", searchCombo) { SwitcherController.shared.openSearch() }
            }
            .store(in: &cancellables)
        $query
            .sink { [weak self] _ in self?.selection = 0 }
            .store(in: &cancellables)
    }

    private func step(by delta: Int, combo: HotKeyCombo) {
        guard AX.ensureTrusted(for: "the window switcher") else { return }
        if panel.isVisible {
            let count = results.count
            if count > 0 { selection = (selection + delta + count) % count }
            return
        }
        holdModifiers = Self.modifierFlags(combo.modifiers)
        searchMode = false
        show(initialSelection: delta > 0 ? 1 : -1)
        // Also covers a quick tap released before the panel came up: switch right away.
        releaseTimer?.invalidate()
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self, panel.isVisible, !searchMode else { return timer.invalidate() }
            if NSEvent.modifierFlags.intersection(holdModifiers).isEmpty {
                timer.invalidate()
                commit()
            }
        }
    }

    private func openSearch() {
        guard AX.ensureTrusted(for: "the window switcher") else { return }
        if panel.isVisible { return panel.dismiss() }
        holdModifiers = []
        searchMode = true
        show(initialSelection: 0)
    }

    private func show(initialSelection: Int) {
        query = ""
        windows = Self.enumerate()
        Log.write("switcher: opened with \(windows.count) windows, hold=\(!searchMode)")
        let count = windows.count
        selection = count == 0 ? 0 : (initialSelection + count) % count
        panel.present { [weak self] event in self?.handle(event) ?? event }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            if !searchMode && event.modifierFlags.intersection(holdModifiers).isEmpty { commit() }
            return event
        }
        let count = results.count
        switch UInt32(event.keyCode) {
        case KeyCode.escape:
            panel.dismiss()
        case KeyCode.returnKey:
            commit()
        case KeyCode.down, KeyCode.right:
            if count > 0 { selection = (selection + 1) % count }
        case KeyCode.up, KeyCode.left:
            if count > 0 { selection = (selection - 1 + count) % count }
        default:
            // Typing switches a held switcher into search mode.
            if !event.modifierFlags.contains(.command), let chars = event.characters, !chars.isEmpty,
               chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                searchMode = true
            }
            return event
        }
        return nil
    }

    func commit() {
        let list = results
        panel.dismiss()
        guard list.indices.contains(selection) else { return }
        focus(list[selection])
    }

    func focus(_ window: SwitcherWindow) {
        panel.dismiss()
        if window.minimized { AX.setBool(window.element, kAXMinimizedAttribute, false) }
        if window.app.isHidden { window.app.unhide() }
        // CoolMenu is never the active app (non-activating panel), so macOS 14's cooperative
        // activation may ignore activate(); setting AXFrontmost through Accessibility is honored.
        let appElement = AXUIElementCreateApplication(window.app.processIdentifier)
        AX.setBool(appElement, kAXFrontmostAttribute, true)
        window.app.activate(options: [])
        AX.raise(window.element)
    }

    /// Every standard window of every regular app, front-most first; minimized windows last.
    static func enumerate() -> [SwitcherWindow] {
        let order = WindowManager.zOrder()
        var ranked: [(SwitcherWindow, Int)] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            for (i, element) in AX.windows(of: app.processIdentifier).enumerated() {
                let subrole = AX.string(element, kAXSubroleAttribute)
                guard subrole == (kAXStandardWindowSubrole as String) || subrole == (kAXDialogSubrole as String) else { continue }
                let minimized = AX.bool(element, kAXMinimizedAttribute)
                let windowID = AX.windowID(element)
                let title = AX.string(element, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 } ?? app.localizedName ?? "Untitled"
                let rank = windowID.flatMap { order[$0] } ?? (minimized || app.isHidden ? 2_000_000 : 1_000_000)
                let id = windowID.map(String.init) ?? "\(app.processIdentifier)-\(i)"
                ranked.append((SwitcherWindow(id: id, element: element, app: app, title: title, minimized: minimized), rank))
            }
        }
        return ranked.sorted { $0.1 < $1.1 }.map(\.0)
    }

    private static func modifierFlags(_ carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & HotKeyCombo.command != 0 { flags.insert(.command) }
        if carbon & HotKeyCombo.option != 0 { flags.insert(.option) }
        if carbon & HotKeyCombo.control != 0 { flags.insert(.control) }
        if carbon & HotKeyCombo.shift != 0 { flags.insert(.shift) }
        return flags
    }
}

struct SwitcherView: View {
    @ObservedObject var controller: SwitcherController
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = controller.results
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack").foregroundStyle(.secondary)
                TextField("Search windows", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, window in
                            HStack(spacing: 10) {
                                Image(nsImage: window.app.icon ?? NSImage()).resizable().frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(window.title).lineLimit(1)
                                    Text(window.appName + (window.minimized ? " · minimized" : ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(index == controller.selection ? Color.accentColor.opacity(0.25) : .clear))
                            .contentShape(Rectangle())
                            .id(window.id)
                            .onTapGesture { controller.focus(window) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: controller.selection) { _, newValue in
                    if items.indices.contains(newValue) { proxy.scrollTo(items[newValue].id) }
                }
            }
            if items.isEmpty {
                Text(AX.isTrusted ? "No windows" : "Grant Accessibility to list windows")
                    .foregroundStyle(.secondary).padding()
            }
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { searchFocused = true }
    }
}
