import Foundation

public enum WindowAction: Codable, Hashable {
    /// Cycles through the named zones of the layout for the window's screen.
    case zones([String])
    case autoLayout
    case nextDisplay
    case previousDisplay

    public var summary: String {
        switch self {
        case .zones(let names): return names.isEmpty ? "No zones" : names.joined(separator: " → ")
        case .autoLayout: return "Auto-layout screen"
        case .nextDisplay: return "Move to next display"
        case .previousDisplay: return "Move to previous display"
        }
    }
}

public struct WindowBinding: Codable, Identifiable, Hashable {
    public var id: UUID
    public var combo: HotKeyCombo
    public var action: WindowAction

    public init(id: UUID = UUID(), combo: HotKeyCombo, action: WindowAction) {
        self.id = id
        self.combo = combo
        self.action = action
    }
}

public enum DefaultLayouts {
    public static var all: [ZoneLayout] { [standard, ultrawide, portrait] }

    private static let shared: [Zone] = [
        Zone(name: "Maximize", x: 0, y: 0, width: 1, height: 1),
        Zone(name: "Center", x: 0.15, y: 0.1, width: 0.7, height: 0.8),
        Zone(name: "Top Half", x: 0, y: 0, width: 1, height: 0.5),
        Zone(name: "Bottom Half", x: 0, y: 0.5, width: 1, height: 0.5),
    ]

    public static var standard: ZoneLayout {
        ZoneLayout(name: "Standard", orientation: .landscape, zones: shared + [
            Zone(name: "Left Half", x: 0, y: 0, width: 0.5, height: 1),
            Zone(name: "Right Half", x: 0.5, y: 0, width: 0.5, height: 1),
            Zone(name: "Left Third", x: 0, y: 0, width: 1.0 / 3, height: 1),
            Zone(name: "Center Third", x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
            Zone(name: "Right Third", x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
            Zone(name: "Left Two Thirds", x: 0, y: 0, width: 2.0 / 3, height: 1),
            Zone(name: "Right Two Thirds", x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1),
            Zone(name: "Top Left", x: 0, y: 0, width: 0.5, height: 0.5),
            Zone(name: "Top Right", x: 0.5, y: 0, width: 0.5, height: 0.5),
            Zone(name: "Bottom Left", x: 0, y: 0.5, width: 0.5, height: 0.5),
            Zone(name: "Bottom Right", x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])
    }

    /// Wide displays: halves feel too wide, so the left/right cycles start at a third.
    public static var ultrawide: ZoneLayout {
        ZoneLayout(name: "Ultrawide", orientation: .landscape, minWidth: 3000, zones: shared + [
            Zone(name: "Left Third", x: 0, y: 0, width: 1.0 / 3, height: 1),
            Zone(name: "Center Third", x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
            Zone(name: "Right Third", x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
            Zone(name: "Left Half", x: 0, y: 0, width: 0.5, height: 1),
            Zone(name: "Right Half", x: 0.5, y: 0, width: 0.5, height: 1),
            Zone(name: "Left Two Thirds", x: 0, y: 0, width: 2.0 / 3, height: 1),
            Zone(name: "Right Two Thirds", x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1),
            Zone(name: "Left Quarter", x: 0, y: 0, width: 0.25, height: 1),
            Zone(name: "Right Quarter", x: 0.75, y: 0, width: 0.25, height: 1),
            Zone(name: "Center Half", x: 0.25, y: 0, width: 0.5, height: 1),
        ])
    }

    /// Vertical displays: stacked areas only.
    public static var portrait: ZoneLayout {
        ZoneLayout(name: "Vertical", orientation: .portrait, zones: shared + [
            Zone(name: "Top Third", x: 0, y: 0, width: 1, height: 1.0 / 3),
            Zone(name: "Middle Third", x: 0, y: 1.0 / 3, width: 1, height: 1.0 / 3),
            Zone(name: "Bottom Third", x: 0, y: 2.0 / 3, width: 1, height: 1.0 / 3),
            Zone(name: "Top Two Thirds", x: 0, y: 0, width: 1, height: 2.0 / 3),
            Zone(name: "Bottom Two Thirds", x: 0, y: 1.0 / 3, width: 1, height: 2.0 / 3),
        ])
    }
}

public enum DefaultBindings {
    private static let ctrlOpt = HotKeyCombo.control | HotKeyCombo.option

    private static func bind(_ key: UInt32, _ action: WindowAction, extra: UInt32 = 0) -> WindowBinding {
        WindowBinding(combo: HotKeyCombo(keyCode: key, modifiers: ctrlOpt | extra), action: action)
    }

    public static var window: [WindowBinding] {
        [
            bind(KeyCode.left, .zones(["Left Half", "Left Third", "Left Two Thirds"])),
            bind(KeyCode.right, .zones(["Right Half", "Right Third", "Right Two Thirds"])),
            bind(KeyCode.up, .zones(["Top Half", "Top Third", "Top Two Thirds"])),
            bind(KeyCode.down, .zones(["Bottom Half", "Bottom Third", "Bottom Two Thirds"])),
            bind(KeyCode.returnKey, .zones(["Maximize"])),
            bind(KeyCode.c, .zones(["Center", "Center Half"])),
            bind(KeyCode.u, .zones(["Top Left"])),
            bind(KeyCode.i, .zones(["Top Right"])),
            bind(KeyCode.j, .zones(["Bottom Left"])),
            bind(KeyCode.k, .zones(["Bottom Right"])),
            bind(KeyCode.d, .zones(["Left Third", "Left Quarter"])),
            bind(KeyCode.f, .zones(["Center Third", "Middle Third"])),
            bind(KeyCode.g, .zones(["Right Third", "Right Quarter"])),
            bind(KeyCode.a, .autoLayout),
            bind(KeyCode.right, .nextDisplay, extra: HotKeyCombo.command),
            bind(KeyCode.left, .previousDisplay, extra: HotKeyCombo.command),
        ]
    }
}

public enum DefaultExclusions {
    /// Password managers and credential stores: never recorded.
    public static let clipboardBundleIDs: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]
}
