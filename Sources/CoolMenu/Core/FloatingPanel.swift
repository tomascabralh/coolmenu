import AppKit
import SwiftUI

/// A Spotlight-style panel: takes keyboard focus without activating CoolMenu, so the app the user
/// was in stays frontmost (which is what makes paste-into-previous-app work).
final class FloatingPanel: NSPanel {
    var onClose: (() -> Void)?
    private var keyMonitor: Any?

    init<Content: View>(size: NSSize, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = NSHostingView(rootView: content())
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Clicking anywhere else dismisses the panel.
    override func resignKey() {
        super.resignKey()
        if isVisible { dismiss() }
    }

    /// Shows centered on the mouse's screen. `handler` sees key and modifier events first;
    /// return nil to swallow one.
    func present(handler: @escaping (NSEvent) -> NSEvent?) {
        if let screen = NSScreen.withMouse() {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2 + f.height * 0.1))
        }
        removeMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, event.window === self else { return event }
            return handler(event)
        }
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        // orderOut resigns key, which calls back into dismiss; the monitor doubles as the guard.
        guard keyMonitor != nil else { return }
        removeMonitor()
        orderOut(nil)
        onClose?()
    }

    private func removeMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

enum KeySynth {
    /// Posts ⌘V to whatever app is frontmost. Requires Accessibility.
    static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
