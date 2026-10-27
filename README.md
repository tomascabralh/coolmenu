# CoolMenu

A macOS menubar suite: window tiling, clipboard history, a window switcher, a system monitor
with disk clean, display dimming and a keyboard cleaning mode. Everything is unlocked and local;
nothing is synced or sent anywhere.

Requires macOS 14+. Builds with Xcode Command Line Tools alone (no Xcode project).

## Build and run

```sh
scripts/build-app.sh --open     # release build -> build/CoolMenu.app, then launch
swift run CoolMenuChecks        # core logic checks (geometry, cycling, grouping, history, shortcuts)
scripts/package.sh              # release zip + dmg in dist/
```

On first launch, grant **Accessibility** in System Settings > Privacy & Security. It drives
window moves, paste, the switcher and keyboard lock.

Run `scripts/make-dev-cert.sh` once first. It creates a self-signed "CoolMenu Dev" signing identity,
which the build script then picks up automatically. Without it, builds are ad-hoc signed, the
signature changes every build, and macOS silently stops honoring the Accessibility grant (the
toggle still shows on). The fix then is to remove CoolMenu from the list and add it again.

## Distributing

`scripts/package.sh` writes `dist/CoolMenu-<version>.zip` and `.dmg` (drag to Applications). The
version is `CFBundleShortVersionString` in `Resources/Info.plist`; the build number is the commit
count. Without a Developer ID the build is self-signed, so on other Macs Gatekeeper blocks it until
you right-click > Open. With a paid developer account, set `COOLMENU_SIGN_IDENTITY` to your
"Developer ID Application" identity and `COOLMENU_NOTARY_PROFILE` to a `notarytool` keychain
profile, and the script notarizes and staples both. Details are in the script header.

CI (GitHub Actions) builds, runs the checks and uploads an ad-hoc signed app on every push and PR.

## Modules

| Module | Default shortcut | Notes |
|---|---|---|
| Window zones | ⌃⌥ ←→↑↓, ↩ maximize, C center, U/I/J/K quarters, D/F/G thirds | Pressing again cycles a binding's zones. Separate layouts per orientation and minimum width (standard, ultrawide ≥ 3000 pt, vertical). |
| Move to display | ⌃⌥⌘ ← / → | Keeps the window's relative position and size. |
| Auto-layout | ⌃⌥A | Tiles the focused display. Optional: re-tile automatically when windows open or close. |
| Clipboard history | ⌘⇧V | Search content, app, window title, file name. ↩ paste, ⇧↩ plain text, ⌘1–9 quick paste, ⌘P pin, ⌘⌫ delete. Unlimited by default. Skips password managers and concealed content. |
| Window switcher | ⌥Tab (⌥⇧Tab back), ⌃⌥Space search | Hold and tap, release to switch; a quick tap goes to the previous window. |
| System monitor | menubar | CPU, memory, disk, CPU sparkline; apps with helpers and child processes grouped. Optional CPU % in the menubar. |
| Disk clean | Settings > System | Caches, logs, DerivedData, npm, pnpm, Gradle. Moves to the Trash, never deletes. |
| Display dimming | menubar, Settings > Displays | Software (gamma) dimming per display, works on any monitor. |
| Keyboard cleaning | menubar, Settings > Keyboard | Blocks all keys; the mouse unlocks, and it times out on its own. |

All shortcuts, zones and layouts are editable in Settings. A shortcut that clashes with another
CoolMenu shortcut (including the switcher's ⇧ reverse step), or that macOS refuses, gets a warning
icon in Settings; hover it to see what it clashes with.

## Data

`~/Library/Application Support/CoolMenu/`: `settings.json`, `history.json`, and `clips/` (images
and rich text). Delete the folder to reset.

## License

[MIT](LICENSE)
