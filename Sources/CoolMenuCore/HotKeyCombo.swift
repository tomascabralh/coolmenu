import Foundation

/// A global shortcut stored as a virtual key code plus Carbon modifier flags.
public struct HotKeyCombo: Codable, Hashable {
    // Carbon modifier bits (cmdKey, shiftKey, optionKey, controlKey from HIToolbox/Events.h).
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + KeyNames.label(for: keyCode)
    }
}

/// Virtual key codes (ANSI layout) used by the defaults, and their labels.
public enum KeyCode {
    public static let a: UInt32 = 0
    public static let s: UInt32 = 1
    public static let d: UInt32 = 2
    public static let f: UInt32 = 3
    public static let g: UInt32 = 5
    public static let c: UInt32 = 8
    public static let v: UInt32 = 9
    public static let e: UInt32 = 14
    public static let t: UInt32 = 17
    public static let u: UInt32 = 32
    public static let i: UInt32 = 34
    public static let j: UInt32 = 38
    public static let k: UInt32 = 40
    public static let returnKey: UInt32 = 36
    public static let tab: UInt32 = 48
    public static let space: UInt32 = 49
    public static let delete: UInt32 = 51
    public static let escape: UInt32 = 53
    public static let left: UInt32 = 123
    public static let right: UInt32 = 124
    public static let down: UInt32 = 125
    public static let up: UInt32 = 126
}

public enum KeyNames {
    private static let labels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 117: "⌦",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public static func label(for keyCode: UInt32) -> String {
        labels[keyCode] ?? "Key \(keyCode)"
    }
}
