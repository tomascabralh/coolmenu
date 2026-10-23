import AppKit
import SwiftUI

@main
struct CoolMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var monitor = SystemMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
        } label: {
            if store.settings.showCPUInMenuBar {
                HStack(spacing: 3) {
                    Image(systemName: "square.grid.2x2")
                    Text("\(Int((monitor.cpu * 100).rounded()))%").monospacedDigit()
                }
            } else {
                Image(systemName: "square.grid.2x2")
            }
        }
        .menuBarExtraStyle(.window)

        Window("CoolMenu Settings", id: SettingsWindow.id) {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum SettingsWindow {
    static let id = "settings"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AX.configureTimeout()
        // pkill / logout send SIGTERM, which skips applicationWillTerminate; route it through
        // terminate so pending saves are flushed and gamma is restored.
        signal(SIGTERM, SIG_IGN)
        termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource?.setEventHandler { NSApp.terminate(nil) }
        termSource?.resume()
        WindowManager.shared.start()
        ClipboardService.shared.start()
        ClipboardPanelController.shared.start()
        SwitcherController.shared.start()
        SystemMonitor.shared.start()
        DimmingService.shared.start()
        Log.write("launch: accessibility trusted=\(AX.isTrusted)")
        if !AX.isTrusted { AX.requestTrust() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeyboardCleaner.shared.stop()
        DimmingService.shared.restoreAll()
        SettingsStore.shared.flush()
        ClipboardService.shared.flush()
    }
}
