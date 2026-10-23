import Foundation

public struct AppSettings: Codable, Equatable {
    // Window manager
    public var layouts: [ZoneLayout] = DefaultLayouts.all
    public var windowBindings: [WindowBinding] = DefaultBindings.window
    public var windowGap: Double = 0
    public var autoLayoutEnabled = false
    public var autoLayoutGap: Double = 8

    // Clipboard
    public var clipboardEnabled = true
    public var clipboardHotKey = HotKeyCombo(keyCode: KeyCode.v, modifiers: HotKeyCombo.command | HotKeyCombo.shift)
    /// 0 keeps everything.
    public var clipboardLimit = 0
    public var clipboardExcludedBundleIDs: [String] = DefaultExclusions.clipboardBundleIDs
    public var clipboardIgnoreConcealed = true

    // Switcher
    public var switcherEnabled = true
    public var switcherHotKey = HotKeyCombo(keyCode: KeyCode.tab, modifiers: HotKeyCombo.option)
    public var switcherSearchHotKey = HotKeyCombo(keyCode: KeyCode.space, modifiers: HotKeyCombo.control | HotKeyCombo.option)

    // System monitor
    public var showCPUInMenuBar = false

    // Dimming: display UUID -> brightness multiplier (0.1...1)
    public var dimLevels: [String: Double] = [:]

    // Keyboard cleaning
    public var keyboardCleanTimeout: Double = 120

    public init() {}

    enum CodingKeys: String, CodingKey {
        case layouts, windowBindings, windowGap, autoLayoutEnabled, autoLayoutGap, clipboardEnabled, clipboardHotKey, clipboardLimit, clipboardExcludedBundleIDs, clipboardIgnoreConcealed, switcherEnabled, switcherHotKey, switcherSearchHotKey, showCPUInMenuBar, dimLevels, keyboardCleanTimeout
    }

    /// Each key falls back to its default when missing or invalid, so adding a setting (or one
    /// corrupt value) never throws away the rest of the user's configuration.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        layouts = c.value(.layouts, default: d.layouts)
        windowBindings = c.value(.windowBindings, default: d.windowBindings)
        windowGap = c.value(.windowGap, default: d.windowGap)
        autoLayoutEnabled = c.value(.autoLayoutEnabled, default: d.autoLayoutEnabled)
        autoLayoutGap = c.value(.autoLayoutGap, default: d.autoLayoutGap)
        clipboardEnabled = c.value(.clipboardEnabled, default: d.clipboardEnabled)
        clipboardHotKey = c.value(.clipboardHotKey, default: d.clipboardHotKey)
        clipboardLimit = c.value(.clipboardLimit, default: d.clipboardLimit)
        clipboardExcludedBundleIDs = c.value(.clipboardExcludedBundleIDs, default: d.clipboardExcludedBundleIDs)
        clipboardIgnoreConcealed = c.value(.clipboardIgnoreConcealed, default: d.clipboardIgnoreConcealed)
        switcherEnabled = c.value(.switcherEnabled, default: d.switcherEnabled)
        switcherHotKey = c.value(.switcherHotKey, default: d.switcherHotKey)
        switcherSearchHotKey = c.value(.switcherSearchHotKey, default: d.switcherSearchHotKey)
        showCPUInMenuBar = c.value(.showCPUInMenuBar, default: d.showCPUInMenuBar)
        dimLevels = c.value(.dimLevels, default: d.dimLevels)
        keyboardCleanTimeout = c.value(.keyboardCleanTimeout, default: d.keyboardCleanTimeout)
    }
}

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
