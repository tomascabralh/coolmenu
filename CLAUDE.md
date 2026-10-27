# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

CoolMenu: native macOS menubar suite (Swift 5.10, SwiftUI + AppKit, SwiftPM, macOS 14+).
Personal project, not a Convey product.

## Commands

- `scripts/build-app.sh [--open] [--debug]`: builds `build/CoolMenu.app` (Info.plist from `Resources/`).
  `--open` kills any running instance first and waits for it to exit before launching.
- `scripts/package.sh`: release zip + dmg into `dist/`. Notarizes only when `COOLMENU_SIGN_IDENTITY`
  is a Developer ID and `COOLMENU_NOTARY_PROFILE` is set; otherwise warns and ships self-signed.
- `swift scripts/make-icon.swift`: regenerates `Resources/AppIcon.icns` (drawn in code, committed).
- `scripts/make-dev-cert.sh`: run once per machine. Creates the self-signed "CoolMenu Dev" identity
  the build script signs with. Without it builds are ad-hoc signed, the signature changes every
  build, and macOS silently stops honoring the Accessibility grant (the toggle still shows on).
  If AX calls mysteriously fail after a rebuild, this is why: remove CoolMenu from the list and re-add it.
- `swift build`: compile check only. A bare binary from `.build/` runs without a bundle, so
  Accessibility, launch-at-login and LSUIElement behave differently. Test through the `.app`.
- `swift run CoolMenuChecks`: assertion-based checks for `CoolMenuCore`. This machine has Command
  Line Tools only, so XCTest is unavailable. It's one script (`Sources/CoolMenuChecks/main.swift`)
  of `check(cond, "message")` calls grouped by `// MARK:`; there is no per-test filter (it always
  runs everything) and it exits non-zero on any failure. Add checks there when you
  change core logic.
- Debugging: the app appends to `~/Library/Application Support/CoolMenu/coolmenu.log` via
  `Log.write` (the unified log is often unreadable without admin). Settings, clipboard history and
  `clips/` live in the same folder; deleting it resets everything.

## Layout

- `Sources/CoolMenuCore`: pure logic, no AppKit (zones, layout picking, cycling, grid, coordinate
  flip, clipboard history, process grouping, fuzzy match, settings model). Everything testable lives here.
- `Sources/CoolMenu`: one folder per module plus `Core/` (settings store, Carbon hotkeys, AX helpers,
  floating panel) and `UI/` (menubar dashboard, settings window).

## How it fits together

- `App/CoolMenuApp.swift` is a SwiftUI `MenuBarExtra` + a settings `Window`, with an `AppDelegate`
  that sets `.accessory` activation and calls `start()` on each module singleton (`.shared`). A new
  module needs a `start()` there and, if it holds state, cleanup in `applicationWillTerminate`.
  SIGTERM is routed to `NSApp.terminate` so quit-time flushes and gamma restore also run on `pkill`.
- Settings: `AppSettings` (in Core, `Codable`) is the single model. Decoding is per-field tolerant:
  a missing or malformed key falls back to its default instead of failing the whole file. Add new
  fields the same way, plus a round-trip check. `SettingsStore` saves debounced to `settings.json`
  (an undecodable file is kept as `settings.unreadable.json`), and modules react via
  `SettingsStore.shared.observe(\.keyPath)` rather than reading settings once at start.

## Invariants and gotchas

- **Coordinates:** Zone fractions use a top-left origin. AppKit frames use bottom-left, AX/CG
  top-left, and they're flipped against the *primary* screen's height (`Coordinates.toAX/toAppKit`).
  Never mix the two.
- **Hotkeys** go through `HotKeyCenter` (Carbon, no permission). Each module owns a group and
  re-registers it from `SettingsStore.observe`. `KeyRecorder` suspends all hotkeys while recording.
  `HotKeyConflicts.uses(in:)` (Core) must mirror what the modules actually register, or Settings'
  clash warnings drift; a new module shortcut goes in both places. Carbon refuses a duplicate combo
  within the process, and `HotKeyCenter.failed` reports refused registrations.
- **iCloud Desktop:** the repo may sit in a synced folder, whose file provider tags bundles with
  FinderInfo and breaks `codesign` at random. `build-app.sh` therefore signs in a temp dir and marks
  `build/` with `com.apple.fileprovider.ignore#P`. Don't "simplify" that back to in-place signing.
- **Panels** (clipboard, switcher) are non-activating `FloatingPanel`s, so the previous app stays
  frontmost and synthesized ⌘V lands there. Don't activate CoolMenu before pasting.
- **Clipboard** history is local-only by design: no iCloud or any sync. Concealed/transient
  pasteboard types and password-manager bundle IDs are skipped.
- **Disk clean** only ever moves to the Trash. Keep it that way.
- **Dimming** uses gamma tables, which macOS resets on display changes and wake. `DimmingService`
  re-applies them, and `applicationWillTerminate` restores them.
- **Keyboard cleaning** must always be escapable: mouse button, plus a timeout.
- Private APIs used: `_AXUIElementGetWindow` (silgen), `responsibility_get_pid_responsible_for_pid` (dlsym).
- No App Sandbox (Accessibility and event taps need it off), so no Mac App Store.

## Not built (yet)

- iCloud sync (needs a paid developer account + CloudKit entitlements).
- DDC/CI hardware brightness. Dimming is software only.
- Browser tabs in the switcher, and window thumbnails (would need Screen Recording / ScreenCaptureKit).
- Drag-to-snap. Zones are keyboard-driven only.
