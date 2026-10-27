import CoolMenuCore
import CoreGraphics
import Foundation

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

// MARK: Zones

let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
let leftHalf = Zone(name: "L", x: 0, y: 0, width: 0.5, height: 1).frame(in: visible)
check(leftHalf == CGRect(x: 0, y: 0, width: 500, height: 800), "left half fills left side")

let topHalf = Zone(name: "T", x: 0, y: 0, width: 1, height: 0.5).frame(in: visible)
check(topHalf == CGRect(x: 0, y: 400, width: 1000, height: 400), "top half sits at the top in AppKit coordinates")

let offset = CGRect(x: 1440, y: 25, width: 1000, height: 800)
check(Zone(name: "BR", x: 0.5, y: 0.5, width: 0.5, height: 0.5).frame(in: offset)
    == CGRect(x: 1940, y: 25, width: 500, height: 400), "zones respect screen origin")

// MARK: Layout picking

let layouts = DefaultLayouts.all
check(LayoutPicker.pick(layouts, for: CGSize(width: 1512, height: 982))?.name == "Standard", "laptop gets standard")
check(LayoutPicker.pick(layouts, for: CGSize(width: 3440, height: 1440))?.name == "Ultrawide", "ultrawide gets ultrawide")
check(LayoutPicker.pick(layouts, for: CGSize(width: 1080, height: 1920))?.name == "Vertical", "portrait gets vertical")
check(LayoutPicker.pick([], for: CGSize(width: 1, height: 1)) == nil, "no layouts -> nil")

// MARK: Cycling

let a = CGRect(x: 0, y: 0, width: 500, height: 800)
let b = CGRect(x: 0, y: 0, width: 333, height: 800)
let c = CGRect(x: 0, y: 0, width: 667, height: 800)
let elsewhere = CGRect(x: 200, y: 100, width: 300, height: 300)
check(ZoneCycler.nextIndex(current: elsewhere, candidates: [a, b, c], lastIndex: nil, lastResult: nil) == 0, "start at first zone")
check(ZoneCycler.nextIndex(current: a, candidates: [a, b, c], lastIndex: nil, lastResult: nil) == 1, "advance from matching zone")
check(ZoneCycler.nextIndex(current: c, candidates: [a, b, c], lastIndex: nil, lastResult: nil) == 0, "wrap around")
let snapped = CGRect(x: 0, y: 0, width: 497, height: 790)
check(ZoneCycler.nextIndex(current: snapped, candidates: [a, b, c], lastIndex: 0, lastResult: snapped) == 1,
      "advance when window kept its last placement even if inexact")
check(ZoneCycler.nextIndex(current: elsewhere, candidates: [a, b, c], lastIndex: 1, lastResult: snapped) == 0,
      "moved window restarts the cycle")
check(ZoneCycler.nextIndex(current: a, candidates: [], lastIndex: nil, lastResult: nil) == nil, "no candidates")
check(ZoneCycler.nextIndex(current: a, candidates: [a], lastIndex: 0, lastResult: a) == 0, "single zone stays put")
check(ZoneCycler.nextIndex(current: elsewhere, candidates: [a, b], lastIndex: 5, lastResult: nil) == 0,
      "stale index without a last result restarts")

// MARK: Grid

let grid1 = GridLayout.frames(count: 1, in: visible, gap: 0)
check(grid1 == [visible], "single window fills the area")
let grid2 = GridLayout.frames(count: 2, in: visible, gap: 0)
check(grid2 == [CGRect(x: 0, y: 0, width: 500, height: 800), CGRect(x: 500, y: 0, width: 500, height: 800)], "two side by side")
let grid3 = GridLayout.frames(count: 3, in: visible, gap: 0)
check(grid3.count == 3 && grid3[2] == CGRect(x: 0, y: 0, width: 1000, height: 400), "odd last row stretches")
check(grid3[0] == CGRect(x: 0, y: 400, width: 500, height: 400), "first row on top")
let gapped = GridLayout.frames(count: 2, in: visible, gap: 10)
check(gapped[0] == CGRect(x: 10, y: 10, width: 485, height: 780), "gaps inset the grid")

// MARK: Coordinates

let r = CGRect(x: 10, y: 20, width: 100, height: 50)
check(ScreenCoordinates.flip(ScreenCoordinates.flip(r, primaryHeight: 900), primaryHeight: 900) == r, "flip is an involution")
check(ScreenCoordinates.flip(r, primaryHeight: 900) == CGRect(x: 10, y: 830, width: 100, height: 50), "flip math")
let moved = ScreenCoordinates.remap(CGRect(x: 0, y: 0, width: 500, height: 400), from: visible, to: CGRect(x: 1000, y: 0, width: 2000, height: 1600))
check(moved == CGRect(x: 1000, y: 0, width: 1000, height: 800), "remap scales to target display")

// MARK: Hot keys

check(HotKeyCombo(keyCode: KeyCode.left, modifiers: HotKeyCombo.control | HotKeyCombo.option).displayString == "⌃⌥←", "display string")
let settings = AppSettings()
let roundTrip = try! JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
check(roundTrip == settings, "settings survive JSON round trip")
let partial = try! JSONDecoder().decode(AppSettings.self, from: Data(#"{"windowGap": 12, "clipboardLimit": "bad"}"#.utf8))
check(partial.windowGap == 12 && partial.clipboardLimit == 0 && partial.layouts.map(\.name) == settings.layouts.map(\.name),
      "missing and invalid keys fall back per key, valid ones survive")
check(HotKeyConflicts.duplicates(in: settings).isEmpty, "default shortcuts don't collide, including the switcher's reverse step")
check(HotKeyCombo(keyCode: KeyCode.v, modifiers: HotKeyCombo.command | HotKeyCombo.shift).displayString == "⇧⌘V", "modifier order")
check(KeyNames.label(for: KeyCode.space) == "Space" && KeyNames.label(for: 999) == "Key 999", "key labels with fallback")

let windowAction = WindowAction.zones(["Left Half", "Left Third"])
check(try! JSONDecoder().decode(WindowAction.self, from: JSONEncoder().encode(windowAction)) == windowAction,
      "window actions with zones survive JSON round trip")

// MARK: Shortcut conflicts

let ctrlOpt = HotKeyCombo.control | HotKeyCombo.option
let optTab = HotKeyCombo(keyCode: KeyCode.tab, modifiers: HotKeyCombo.option)
let optShiftTab = HotKeyCombo(keyCode: KeyCode.tab, modifiers: HotKeyCombo.option | HotKeyCombo.shift)
check(HotKeyConflicts.switcherReverse(of: optTab) == optShiftTab && HotKeyConflicts.switcherReverse(of: optShiftTab) == nil,
      "switcher reverse adds shift, none when shift is already held")

var clash = AppSettings()
clash.clipboardHotKey = optShiftTab
check(HotKeyConflicts.duplicates(in: clash)[optShiftTab]?.sorted() == ["Clipboard history", "Switch windows backwards"],
      "implicit reverse step counts as a use")
check(HotKeyConflicts.conflicts(label: HotKeyConflicts.switcherLabel, combo: optTab, in: clash) == ["Clipboard history"],
      "switcher recorder warns about a clash on its reverse step")
check(HotKeyConflicts.conflicts(label: HotKeyConflicts.clipboardLabel, combo: optShiftTab, in: clash) == ["Switch windows backwards"],
      "the other side of the clash warns too")
clash.switcherEnabled = false
check(HotKeyConflicts.duplicates(in: clash).isEmpty, "a disabled switcher registers nothing")
check(HotKeyConflicts.conflicts(label: HotKeyConflicts.switcherSearchLabel, combo: clash.switcherSearchHotKey, in: clash).isEmpty,
      "unregistered shortcut never conflicts")

var twins = AppSettings()
let blank = WindowBinding(combo: HotKeyCombo(keyCode: KeyCode.e, modifiers: ctrlOpt | HotKeyCombo.shift), action: .zones([]))
twins.windowBindings += [blank, WindowBinding(combo: blank.combo, action: .zones([]))]
check(HotKeyConflicts.conflicts(label: HotKeyConflicts.label(for: blank), combo: blank.combo, in: twins) == ["Windows: No zones"],
      "two identical bindings still flag each other")
check(HotKeyConflicts.conflicts(label: HotKeyConflicts.clipboardLabel, combo: twins.clipboardHotKey, in: twins).isEmpty,
      "unique shortcut has no conflicts")

// MARK: Defaults

let allZoneNames = Set(DefaultLayouts.all.flatMap(\.zones).map(\.name))
let boundZoneNames = DefaultBindings.window.flatMap { binding -> [String] in
    if case .zones(let names) = binding.action { return names }
    return []
}
check(boundZoneNames.allSatisfy(allZoneNames.contains), "every default binding names a zone some default layout has")
for layout in DefaultLayouts.all {
    check(Set(layout.zones.map(\.name)).count == layout.zones.count, "\(layout.name): zone names are unique")
    check(layout.zones.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.width > 0 && $0.height > 0
        && $0.x + $0.width <= 1 + 1e-9 && $0.y + $0.height <= 1 + 1e-9 }, "\(layout.name): zones stay on screen")
}

// MARK: Clipboard history

func clip(_ text: String, pinned: Bool = false) -> ClipItem {
    ClipItem(kind: .text, text: text, appName: "Notes", pinned: pinned, contentHash: StableHash.of(text))
}

var history = ClipHistory()
history.insert(clip("alpha"), limit: 0)
history.insert(clip("beta"), limit: 0)
history.insert(clip("alpha"), limit: 0)
check(history.items.map(\.text) == ["alpha", "beta"], "duplicate moves to top")

history.togglePin(id: history.items[1].id)
history.insert(clip("gamma"), limit: 1)
check(history.items.map(\.text) == ["gamma", "beta"], "limit evicts unpinned, keeps pinned")
check(history.search("").first?.text == "beta", "pinned listed first")
check(history.search("GAM").map(\.text) == ["gamma"], "case-insensitive content search")
check(history.search("notes gam").map(\.text) == ["gamma"], "tokens match across app and content")
check(history.search("zzz").isEmpty, "no match")
let cleared = history.clearUnpinned()
check(cleared.map(\.text) == ["gamma"] && history.items.map(\.text) == ["beta"], "clear keeps pinned")
check(StableHash.of("hello") == StableHash.of("hello") && StableHash.of("hello") != StableHash.of("hellp"), "stable hash")

let files = ClipItem(kind: .files, filePaths: ["/Users/x/Report Q3.pdf"], contentHash: 1)
check(ClipHistory(items: [files]).search("report").count == 1, "search by file name")

// MARK: Processes

let samples = [
    ProcessSample(pid: 100, ppid: 1, name: "Google Chrome", cpuPercent: 5, memoryBytes: 100),
    ProcessSample(pid: 101, ppid: 100, name: "Google Chrome Helper", cpuPercent: 20, memoryBytes: 300),
    ProcessSample(pid: 102, ppid: 101, name: "Google Chrome Helper (GPU)", cpuPercent: 10, memoryBytes: 50),
    ProcessSample(pid: 200, ppid: 1, responsiblePid: 100, name: "com.google.xpc", cpuPercent: 1, memoryBytes: 10),
    ProcessSample(pid: 300, ppid: 1, name: "zsh", cpuPercent: 0, memoryBytes: 5),
    ProcessSample(pid: 301, ppid: 300, name: "node", cpuPercent: 50, memoryBytes: 500),
]
let groups = ProcessGrouper.group(samples, appRoots: [100], appNames: [100: "Chrome"])
check(groups.count == 2, "two logical parents")
check(groups.first?.name == "zsh" && groups.first?.cpuPercent == 50, "shell tree aggregates under its top ancestor")
let chrome = groups.first { $0.id == 100 }
check(chrome?.name == "Chrome" && chrome?.cpuPercent == 36 && chrome?.memoryBytes == 460, "helpers and XPC aggregate under app")
check(chrome?.members.first?.pid == 101, "members sorted by CPU")

check(abs(CPUTicks.usage(from: CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
                         to: CPUTicks(user: 30, system: 10, idle: 60, nice: 0)) - 0.4) < 1e-9, "cpu usage")

check(ByteFormat.short(1024 * 1024).contains("MB") && ByteFormat.short(3 * 1024 * 1024 * 1024).contains("GB"), "byte units")
check(!ByteFormat.short(.max).isEmpty, "huge byte counts clamp instead of trapping")

// MARK: Fuzzy

check(FuzzyMatch.score("gc", in: "Google Chrome") != nil, "initials match")
check(FuzzyMatch.score("xyz", in: "Google Chrome") == nil, "non-subsequence fails")
check(FuzzyMatch.score("chr", in: "Google Chrome")! > FuzzyMatch.score("ghe", in: "Google Chrome")!, "contiguous word-start wins")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
