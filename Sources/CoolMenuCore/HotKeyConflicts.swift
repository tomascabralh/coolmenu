import Foundation

/// One global shortcut CoolMenu registers, and what it does.
public struct HotKeyUse: Hashable {
    public var combo: HotKeyCombo
    public var label: String

    public init(combo: HotKeyCombo, label: String) {
        self.combo = combo
        self.label = label
    }
}

/// Finds shortcuts registered more than once. Carbon rejects a second registration of the same
/// combo within one process, so a duplicate means one of the two silently never fires.
public enum HotKeyConflicts {
    public static let clipboardLabel = "Clipboard history"
    public static let switcherLabel = "Switch windows"
    public static let switcherReverseLabel = "Switch windows backwards"
    public static let switcherSearchLabel = "Search windows"

    public static func label(for binding: WindowBinding) -> String {
        "Windows: \(binding.action.summary)"
    }

    /// Every shortcut the modules register for `settings`, mirroring their registration code
    /// (including the switcher's implicit ⇧ reverse step).
    public static func uses(in settings: AppSettings) -> [HotKeyUse] {
        var uses = settings.windowBindings.map { HotKeyUse(combo: $0.combo, label: label(for: $0)) }
        uses.append(HotKeyUse(combo: settings.clipboardHotKey, label: clipboardLabel))
        if settings.switcherEnabled {
            let combo = settings.switcherHotKey
            uses.append(HotKeyUse(combo: combo, label: switcherLabel))
            if let reverse = switcherReverse(of: combo) {
                uses.append(HotKeyUse(combo: reverse, label: switcherReverseLabel))
            }
            uses.append(HotKeyUse(combo: settings.switcherSearchHotKey, label: switcherSearchLabel))
        }
        return uses
    }

    /// Combos used more than once, with the labels of everything using them.
    public static func duplicates(in settings: AppSettings) -> [HotKeyCombo: [String]] {
        Dictionary(grouping: uses(in: settings), by: \.combo)
            .filter { $0.value.count > 1 }
            .mapValues { $0.map(\.label) }
    }

    /// The ⇧ variant the switcher registers to step backwards, or nil when `combo` already has ⇧.
    public static func switcherReverse(of combo: HotKeyCombo) -> HotKeyCombo? {
        var reverse = combo
        reverse.modifiers |= HotKeyCombo.shift
        return reverse == combo ? nil : reverse
    }

    /// Labels of the other shortcuts that clash with the one a recorder edits (`label` + `combo`).
    /// The switcher recorder also owns the reverse step. Nothing clashes with a shortcut that
    /// isn't registered (e.g. the switcher while disabled).
    public static func conflicts(label: String, combo: HotKeyCombo, in settings: AppSettings) -> [String] {
        var owned = [HotKeyUse(combo: combo, label: label)]
        if label == switcherLabel, let reverse = switcherReverse(of: combo) {
            owned.append(HotKeyUse(combo: reverse, label: switcherReverseLabel))
        }
        var pool = uses(in: settings)
        for use in owned {
            guard let i = pool.firstIndex(of: use) else { return [] }
            pool.remove(at: i)
        }
        let combos = Set(owned.map(\.combo))
        var seen: Set<String> = []
        return pool.filter { combos.contains($0.combo) }.map(\.label).filter { seen.insert($0).inserted }
    }
}
