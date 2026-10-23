import AppKit
import Combine

/// Software dimming via each display's gamma table. Works on any monitor, including ones without
/// DDC/CI, and dims below the panel's hardware minimum. macOS resets gamma on display changes and
/// wake, so levels are re-applied then, and restored on quit.
final class DimmingService: ObservableObject {
    static let shared = DimmingService()

    struct Display: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let uuid: String
        let name: String
        let builtIn: Bool
    }

    static let minimumLevel = 0.1

    @Published private(set) var displays: [Display] = []

    private let store = SettingsStore.shared
    private var observers: [NSObjectProtocol] = []
    private var levelsCancellable: AnyCancellable?
    /// What the gamma tables currently hold, by display UUID (absent = full brightness).
    private var applied: [String: Double] = [:]

    func start() {
        refresh()
        // Covers changes made outside the sliders, e.g. "Reset all settings".
        levelsCancellable = store.observe(\.dimLevels)
            .dropFirst()
            .sink { [weak self] levels in
                guard let self else { return }
                let connected = Set(displays.map(\.uuid))
                guard levels.filter({ connected.contains($0.key) }) != applied else { return }
                applyAll()
                objectWillChange.send()
            }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Gamma is reset a beat after wake.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.applyAll() }
        })
    }

    func level(for display: Display) -> Double {
        store.settings.dimLevels[display.uuid] ?? 1
    }

    func setLevel(_ level: Double, for display: Display) {
        let clamped = min(max(level, Self.minimumLevel), 1)
        store.settings.dimLevels[display.uuid] = clamped >= 0.999 ? nil : clamped
        apply(display)
        objectWillChange.send()
    }

    func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
    }

    private func refresh() {
        displays = NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
                  let uuidString = CFUUIDCreateString(nil, uuid) as String?
            else { return nil }
            return Display(id: id, uuid: uuidString, name: screen.localizedName, builtIn: CGDisplayIsBuiltin(id) != 0)
        }
        .sorted { ($0.builtIn ? 1 : 0, $0.name) < ($1.builtIn ? 1 : 0, $1.name) }
        applyAll()
    }

    private func applyAll() {
        restoreAll()
        applied = [:]
        for display in displays where level(for: display) < 1 { apply(display) }
    }

    private func apply(_ display: Display) {
        let level = level(for: display)
        let value = Float(level)
        if value >= 0.999 {
            // Restoring is global, so put the other dimmed displays back afterwards.
            restoreAll()
            applied = [:]
            for other in displays where other.id != display.id && self.level(for: other) < 1 { apply(other) }
            return
        }
        applied[display.uuid] = level
        CGSetDisplayTransferByFormula(display.id, 0, value, 1, 0, value, 1, 0, value, 1)
    }
}
