import Carbon.HIToolbox
import Combine
import CoolMenuCore
import Foundation

/// Global shortcuts through Carbon's RegisterEventHotKey: no permission prompt and the key is
/// consumed, so the focused app never sees it. Registrations are grouped so each module can
/// replace its own set when settings change.
final class HotKeyCenter: ObservableObject {
    static let shared = HotKeyCenter()

    private struct Entry {
        let group: String
        let combo: HotKeyCombo
        let handler: () -> Void
        var ref: EventHotKeyRef?
    }

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 1
    private var suspended = false
    /// Combos whose registration was refused (taken by macOS, or registered twice). Settings shows
    /// a warning next to them. Left untouched while suspended, when nothing is registered.
    @Published private(set) var failed: Set<HotKeyCombo> = []
    private static let signature: OSType = 0x434D_4E55 // "CMNU"

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            HotKeyCenter.shared.fire(hotKeyID.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(group: String, _ combo: HotKeyCombo, handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        var entry = Entry(group: group, combo: combo, handler: handler, ref: nil)
        if !suspended { entry.ref = install(combo, id: id) }
        entries[id] = entry
        refreshFailed()
    }

    func unregister(group: String) {
        for (id, entry) in entries where entry.group == group {
            if let ref = entry.ref { UnregisterEventHotKey(ref) }
            entries[id] = nil
        }
        refreshFailed()
    }

    /// Releases every key while a shortcut recorder is listening, so pressing an existing
    /// shortcut reaches the recorder instead of firing.
    func suspend() {
        guard !suspended else { return }
        suspended = true
        for id in entries.keys {
            if let ref = entries[id]?.ref { UnregisterEventHotKey(ref) }
            entries[id]?.ref = nil
        }
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        for (id, entry) in entries {
            entries[id]?.ref = install(entry.combo, id: id)
        }
        refreshFailed()
    }

    private func install(_ combo: HotKeyCombo, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            Log.write("hotkeys: could not register \(combo.displayString) (status \(status)); another app may own it")
        }
        return ref
    }

    private func refreshFailed() {
        guard !suspended else { return }
        let now = Set(entries.values.filter { $0.ref == nil }.map(\.combo))
        if now != failed { failed = now }
    }

    private func fire(_ id: UInt32) {
        entries[id]?.handler()
    }
}
