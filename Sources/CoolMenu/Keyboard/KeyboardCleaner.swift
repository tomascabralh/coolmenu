import AppKit
import SwiftUI

/// Swallows every key event (including media and brightness keys) so the keyboard can be wiped.
/// The mouse stays live: a full-screen overlay holds the unlock button, and a timeout unlocks
/// regardless, so the user can never get stuck.
final class KeyboardCleaner: ObservableObject {
    static let shared = KeyboardCleaner()

    @Published private(set) var active = false
    @Published private(set) var remaining = 0

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var overlays: [NSWindow] = []
    private var countdown: Timer?

    func start() {
        guard !active else { return }
        guard AX.ensureTrusted(for: "keyboard cleaning") else { return }
        // keyDown, keyUp, flagsChanged, and NX_SYSDEFINED (14) for media/brightness keys.
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    KeyboardCleaner.shared.reenable()
                    return Unmanaged.passUnretained(event)
                }
                return nil
            },
            userInfo: nil
        ) else { return }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        active = true
        remaining = Int(SettingsStore.shared.settings.keyboardCleanTimeout)
        showOverlays()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            remaining -= 1
            if remaining <= 0 { stop() }
        }
    }

    func stop() {
        guard active else { return }
        countdown?.invalidate()
        countdown = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        active = false
    }

    private func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func showOverlays() {
        NSApp.activate(ignoringOtherApps: true)
        overlays = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CleaningOverlay(cleaner: self))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
    }
}

private struct CleaningOverlay: View {
    @ObservedObject var cleaner: KeyboardCleaner

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
            VStack(spacing: 18) {
                Image(systemName: "keyboard.badge.ellipsis").font(.system(size: 64, weight: .light))
                Text("Keyboard disabled for cleaning").font(.largeTitle.weight(.semibold))
                Text("Unlocks automatically in \(cleaner.remaining)s").monospacedDigit().foregroundStyle(.secondary)
                Button("Done cleaning") { cleaner.stop() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}
