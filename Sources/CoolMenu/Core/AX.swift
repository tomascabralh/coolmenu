import AppKit
import ApplicationServices
import CoolMenuCore

/// Private but stable since 10.x; used by every macOS window manager to map AX windows to CGWindowIDs.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin helpers over the Accessibility API. Frames here are in AX coordinates (top-left origin).
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// AX calls are synchronous and default to a ~6s timeout per call, so a single hung app would
    /// freeze CoolMenu. Setting it on the system-wide element applies to every element.
    static func configureTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
    }

    private static var prompted = false
    private static var lastAlert = Date.distantPast

    /// Shows the system prompt at most once per launch.
    static func requestTrust() {
        guard !prompted else { return }
        prompted = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Gate for user-triggered features. Returns true when trusted; otherwise says so instead of
    /// failing silently: the system prompt first, then (rate-limited) an alert explaining that a
    /// toggle that looks on can belong to an older build.
    @discardableResult
    static func ensureTrusted(for feature: String) -> Bool {
        if isTrusted { return true }
        Log.write("\(feature): blocked, Accessibility not granted to this build")
        if !prompted { requestTrust(); return false }
        guard Date().timeIntervalSince(lastAlert) > 20 else { return false }
        lastAlert = Date()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "CoolMenu needs Accessibility access"
        alert.informativeText = "\(feature.prefix(1).uppercased() + feature.dropFirst()) can't work without it. If CoolMenu already looks enabled in System Settings, that entry belongs to an older build: select it, remove it with the minus button, then add CoolMenu again."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { openAccessibilitySettings() }
        return false
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AXUIElement]) ?? []
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (copy(element, attribute) as? Bool) ?? false
    }

    static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean)
    }

    static func focusedWindow() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        return element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        elements(AXUIElementCreateApplication(pid), kAXWindowsAttribute)
    }

    static func isStandardWindow(_ window: AXUIElement) -> Bool {
        string(window, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String)
    }

    static func windowID(_ window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let posValue = copy(window, kAXPositionAttribute), let sizeValue = copy(window, kAXSizeAttribute),
              CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// Size, then position, then size again: shrinking first keeps the window from being clamped
    /// when it moves across displays, and the second size fixes apps that resize on move.
    static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var size = frame.size
        var origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let posValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        setBool(window, kAXMainAttribute, true)
    }
}

extension NSScreen {
    /// The primary display's height anchors the AppKit <-> AX coordinate flip.
    static var primaryHeight: CGFloat { screens.first?.frame.height ?? 0 }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Screen holding most of `rect` (AppKit coordinates).
    static func best(for rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let hit = screens.first(where: { $0.frame.contains(center) }) { return hit }
        return screens.max { a, b in
            let ia = a.frame.intersection(rect)
            let ib = b.frame.intersection(rect)
            return ia.width * ia.height < ib.width * ib.height
        } ?? main
    }

    static func withMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? main
    }
}

enum Coordinates {
    static func toAX(_ appKit: CGRect) -> CGRect { ScreenCoordinates.flip(appKit, primaryHeight: NSScreen.primaryHeight) }
    static func toAppKit(_ ax: CGRect) -> CGRect { ScreenCoordinates.flip(ax, primaryHeight: NSScreen.primaryHeight) }
}
