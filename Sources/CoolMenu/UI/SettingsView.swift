import AppKit
import CoolMenuCore
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, windows, clipboard, switcher, monitor, displays, keyboard
}

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general.rawValue)
            WindowSettings().tabItem { Label("Windows", systemImage: "rectangle.3.group") }.tag(SettingsTab.windows.rawValue)
            ClipboardSettings().tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }.tag(SettingsTab.clipboard.rawValue)
            SwitcherSettings().tabItem { Label("Switcher", systemImage: "rectangle.stack") }.tag(SettingsTab.switcher.rawValue)
            MonitorSettings().tabItem { Label("System", systemImage: "gauge.with.dots.needle.33percent") }.tag(SettingsTab.monitor.rawValue)
            DisplaySettings().tabItem { Label("Displays", systemImage: "display") }.tag(SettingsTab.displays.rawValue)
            KeyboardSettings().tabItem { Label("Keyboard", systemImage: "keyboard") }.tag(SettingsTab.keyboard.rawValue)
        }
        .frame(width: 760, height: 560)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            PermissionBanner()
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        // Reverting the toggle after a failure re-enters here; don't overwrite the error.
                        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    Button("Open System Settings") { AX.openAccessibilitySettings() }
                }
                Text("Window moves, paste, the switcher and keyboard cleaning use Accessibility. CoolMenu needs nothing else.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Data") {
                LabeledContent("Stored at") {
                    Button(AppPaths.support.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                        NSWorkspace.shared.open(AppPaths.support)
                    }
                    .buttonStyle(.link)
                }
                Text("Settings and clipboard history stay on this Mac. Nothing is synced or sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset all settings to defaults", role: .destructive) { store.settings = AppSettings() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Windows

private struct WindowSettings: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                Text("Shortcuts").tag(0)
                Text("Zones").tag(1)
                Text("Options").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .padding(.top, 12)
            switch section {
            case 0: BindingsEditor()
            case 1: ZoneEditor()
            default: windowOptions
            }
        }
    }

    private var windowOptions: some View {
        Form {
            Section("Snapping") {
                LabeledContent("Gap between windows") {
                    Stepper("\(Int(store.settings.windowGap)) pt", value: $store.settings.windowGap, in: 0...40, step: 2)
                }
            }
            Section("Auto-layout") {
                Toggle("Re-tile a display whenever a window opens or closes on it", isOn: $store.settings.autoLayoutEnabled)
                LabeledContent("Tile gap") {
                    Stepper("\(Int(store.settings.autoLayoutGap)) pt", value: $store.settings.autoLayoutGap, in: 0...40, step: 2)
                }
                Text("Tile the focused display any time with the Auto-layout shortcut (⌃⌥A by default).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("CoolMenu runs alongside macOS window tiling. If both react to the same drag or shortcut, turn off the overlapping one in System Settings > Desktop & Dock.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BindingsEditor: View {
    @ObservedObject private var store = SettingsStore.shared

    private var zoneNames: [String] {
        var seen: Set<String> = []
        return store.settings.layouts.flatMap(\.zones).map(\.name).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach($store.settings.windowBindings) { $binding in
                    HStack(alignment: .center, spacing: 12) {
                        KeyRecorder(combo: $binding.combo)
                        actionEditor($binding.action)
                        Spacer()
                        Button(role: .destructive) {
                            store.settings.windowBindings.removeAll { $0.id == binding.id }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack {
                Text("Pressing a shortcut again cycles through its zones. Zones missing from a display's layout are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore defaults") { store.settings.windowBindings = DefaultBindings.window }
                Button("Add shortcut") {
                    store.settings.windowBindings.append(WindowBinding(
                        combo: HotKeyCombo(keyCode: KeyCode.e, modifiers: HotKeyCombo.control | HotKeyCombo.option | HotKeyCombo.shift),
                        action: .zones([])
                    ))
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder private func actionEditor(_ action: Binding<WindowAction>) -> some View {
        HStack(spacing: 6) {
            Menu {
                Button("Zones") { action.wrappedValue = .zones([]) }
                Button("Auto-layout screen") { action.wrappedValue = .autoLayout }
                Button("Move to next display") { action.wrappedValue = .nextDisplay }
                Button("Move to previous display") { action.wrappedValue = .previousDisplay }
            } label: {
                Text(kindLabel(action.wrappedValue))
            }
            .fixedSize()

            if case .zones(let names) = action.wrappedValue {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 2) {
                        Text(name)
                        Button {
                            var updated = names
                            updated.remove(at: index)
                            action.wrappedValue = .zones(updated)
                        } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.quaternary))
                }
                Menu {
                    ForEach(zoneNames, id: \.self) { name in
                        Button(name) { action.wrappedValue = .zones(names + [name]) }
                    }
                } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
        }
    }

    private func kindLabel(_ action: WindowAction) -> String {
        switch action {
        case .zones: return "Zones"
        case .autoLayout, .nextDisplay, .previousDisplay: return action.summary
        }
    }
}

private struct ZoneEditor: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var layoutID: UUID?
    @State private var zoneID: UUID?

    private var layoutIndex: Int? {
        store.settings.layouts.firstIndex { $0.id == layoutID } ?? (store.settings.layouts.isEmpty ? nil : 0)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            layoutList.frame(width: 200)
            Divider()
            if let li = layoutIndex {
                layoutDetail($store.settings.layouts[li])
            } else {
                ContentUnavailableView("No layouts", systemImage: "rectangle.3.group")
            }
        }
    }

    private var layoutList: some View {
        VStack(spacing: 0) {
            List(selection: $layoutID) {
                ForEach(store.settings.layouts) { layout in
                    VStack(alignment: .leading) {
                        Text(layout.name)
                        Text("\(layout.orientation.rawValue.capitalized), ≥ \(Int(layout.minWidth)) pt · \(layout.zones.count) zones")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(layout.id)
                }
            }
            HStack {
                Button { addLayout() } label: { Image(systemName: "plus") }
                Button { removeLayout() } label: { Image(systemName: "minus") }.disabled(layoutIndex == nil)
                Spacer()
                Button("Defaults") { store.settings.layouts = DefaultLayouts.all; layoutID = nil }
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .onAppear { if layoutID == nil { layoutID = store.settings.layouts.first?.id } }
    }

    private func layoutDetail(_ layout: Binding<ZoneLayout>) -> some View {
        let selectedIndex = layout.wrappedValue.zones.firstIndex { $0.id == zoneID }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Name", text: layout.name).frame(width: 160)
                Picker("", selection: layout.orientation) {
                    ForEach(Orientation.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
                Text("Min width")
                TextField("", value: layout.minWidth, format: .number).frame(width: 70)
                Text("pt").foregroundStyle(.secondary)
            }
            ZonePreview(layout: layout.wrappedValue, selected: zoneID) { zoneID = $0 }
                .frame(height: layout.wrappedValue.orientation == .portrait ? 220 : 170)
            List(selection: $zoneID) {
                ForEach(layout.zones) { $zone in
                    HStack {
                        TextField("Zone name", text: $zone.name).frame(width: 150)
                        percentField("x", $zone.x)
                        percentField("y", $zone.y)
                        percentField("w", $zone.width)
                        percentField("h", $zone.height)
                    }
                    .tag(zone.id)
                }
            }
            HStack {
                Button("Add zone") {
                    let zone = Zone(name: "New Zone", x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                    layout.wrappedValue.zones.append(zone)
                    zoneID = zone.id
                }
                Button("Delete zone") {
                    if let selectedIndex { layout.wrappedValue.zones.remove(at: selectedIndex) }
                }
                .disabled(selectedIndex == nil)
                Spacer()
                Text("Values are % of the display's usable area, from the top-left. Shortcuts refer to zones by name.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func percentField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: Binding(
                get: { (value.wrappedValue * 1000).rounded() / 10 },
                set: { value.wrappedValue = min(max($0, 0), 100) / 100 }
            ), format: .number)
            .frame(width: 48)
        }
    }

    private func addLayout() {
        let layout = ZoneLayout(name: "Custom", orientation: .landscape, minWidth: 0, zones: DefaultLayouts.standard.zones)
        store.settings.layouts.append(layout)
        layoutID = layout.id
    }

    private func removeLayout() {
        guard let li = layoutIndex else { return }
        store.settings.layouts.remove(at: li)
        layoutID = store.settings.layouts.first?.id
    }
}

private struct ZonePreview: View {
    let layout: ZoneLayout
    let selected: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        GeometryReader { geo in
            let aspect: CGFloat = layout.orientation == .portrait ? 9 / 16 : 16 / 10
            let height = min(geo.size.height, geo.size.width / aspect)
            let size = CGSize(width: height * aspect, height: height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                // Smallest last so overlapping zones stay clickable.
                ForEach(layout.zones.sorted { $0.width * $0.height > $1.width * $1.height }) { zone in
                    let isSelected = zone.id == selected
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(isSelected ? 0.45 : 0.08))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor.opacity(isSelected ? 1 : 0.35)))
                        .overlay(Text(zone.name).font(.caption2).opacity(isSelected ? 1 : 0))
                        .frame(width: size.width * zone.width, height: size.height * zone.height)
                        .offset(x: size.width * zone.x, y: size.height * zone.y)
                        .onTapGesture { onSelect(zone.id) }
                }
            }
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Clipboard

private struct ClipboardSettings: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var clipboard = ClipboardService.shared
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("History") {
                Toggle("Record clipboard history", isOn: $store.settings.clipboardEnabled)
                LabeledContent("Open history") { KeyRecorder(combo: $store.settings.clipboardHotKey) }
                Picker("Keep", selection: $store.settings.clipboardLimit) {
                    Text("Unlimited").tag(0)
                    Text("100 items").tag(100)
                    Text("500 items").tag(500)
                    Text("1,000 items").tag(1000)
                    Text("5,000 items").tag(5000)
                }
                Toggle("Skip passwords and content apps mark as concealed", isOn: $store.settings.clipboardIgnoreConcealed)
                LabeledContent("Stored items") {
                    Text("\(clipboard.history.items.count)")
                }
                Button("Clear history (keeps pinned)", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
                        Button("Clear", role: .destructive) { clipboard.clearUnpinned() }
                    }
            }
            Section("Never record from") {
                ForEach(store.settings.clipboardExcludedBundleIDs, id: \.self) { id in
                    HStack {
                        AppIcon(bundleID: id).frame(width: 18, height: 18)
                        Text(appName(id))
                        Text(id).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { store.settings.clipboardExcludedBundleIDs.removeAll { $0 == id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Add running app") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let id = app.bundleIdentifier { store.settings.clipboardExcludedBundleIDs.append(id) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !store.settings.clipboardExcludedBundleIDs.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

// MARK: Switcher

private struct SwitcherSettings: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("Window switcher") {
                Toggle("Enable", isOn: $store.settings.switcherEnabled)
                LabeledContent("Switch windows") { KeyRecorder(combo: $store.settings.switcherHotKey) }
                LabeledContent("Search windows") { KeyRecorder(combo: $store.settings.switcherSearchHotKey) }
            }
            Section("How it works") {
                Text("Hold the modifier and tap the key to step through windows; release to switch. Add ⇧ to step backwards. A quick tap jumps to your previous window. Start typing while it's open to search by window title or app name.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Lists windows on the current Space. ⌘Tab belongs to macOS and can't be taken over.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: System

private struct MonitorSettings: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var cleaner = DiskCleaner.shared
    @State private var pendingClean: DiskCleaner.Target?
    @State private var expanded: Set<Int32> = []

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            processes
            Divider()
            disk.frame(width: 300)
        }
        .onAppear {
            monitor.setConsumer("settings", active: true)
            cleaner.scan()
        }
        .onDisappear { monitor.setConsumer("settings", active: false) }
    }

    private var processes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show CPU % in the menu bar", isOn: $store.settings.showCPUInMenuBar)
            Text("Apps with their helper and child processes grouped together. Only your own processes are visible without root.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(monitor.groups.prefix(60)) { group in
                    DisclosureGroup(isExpanded: Binding(
                        get: { expanded.contains(group.id) },
                        set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } }
                    )) {
                        ForEach(group.members) { member in
                            row(member.name, cpu: member.cpuPercent, memory: member.memoryBytes, secondary: true)
                        }
                    } label: {
                        row("\(group.name)  (\(group.members.count))", cpu: group.cpuPercent, memory: group.memoryBytes, secondary: false)
                    }
                }
            }
        }
        .padding(12)
    }

    private func row(_ name: String, cpu: Double, memory: UInt64, secondary: Bool) -> some View {
        HStack {
            Text(name).lineLimit(1).foregroundStyle(secondary ? .secondary : .primary)
            Spacer()
            Text(String(format: "%.1f%%", cpu)).monospacedDigit().frame(width: 60, alignment: .trailing)
            Text(ByteFormat.short(memory)).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
        .font(.callout)
    }

    private var disk: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Disk Clean").font(.headline)
                Spacer()
                if cleaner.scanning || cleaner.cleaning { ProgressView().controlSize(.small) }
                Button("Rescan") { cleaner.scan() }.disabled(cleaner.scanning || cleaner.cleaning)
            }
            Text("Moves regenerable files to the Trash so you can undo. Space is freed when you empty the Trash.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cleaner.targets.filter(\.exists)) { target in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.name)
                                Text(target.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(target.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…")
                                    .monospacedDigit()
                                Button("Clean") { pendingClean = target }
                                    .controlSize(.small)
                                    .disabled((target.size ?? 0) == 0 || cleaner.cleaning)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                    }
                }
            }
            if let result = cleaner.lastResult {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
            Text("Total: \(ByteCountFormatter.string(fromByteCount: cleaner.totalSize, countStyle: .file))").font(.caption)
        }
        .padding(12)
        .confirmationDialog(
            "Move the contents of \(pendingClean?.name ?? "") to the Trash?",
            isPresented: Binding(get: { pendingClean != nil }, set: { if !$0 { pendingClean = nil } })
        ) {
            Button("Move to Trash", role: .destructive) {
                if let pendingClean { cleaner.clean(pendingClean) }
                pendingClean = nil
            }
        } message: {
            Text("Apps that are open may need a restart to rebuild their caches.")
        }
    }
}

// MARK: Displays

private struct DisplaySettings: View {
    var body: some View {
        Form {
            Section("Brightness") {
                DisplaySliders()
            }
            Section {
                Text("Dimming is done in software, so it works on every monitor and goes below the panel's own minimum. It's also in the menu bar dashboard. Levels reset if CoolMenu quits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Keyboard

private struct KeyboardSettings: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var cleaner = KeyboardCleaner.shared

    var body: some View {
        Form {
            Section("Keyboard cleaning") {
                Text("Blocks every key, including media and brightness keys, so you can wipe the keyboard while the Mac stays on. The mouse keeps working.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Unlock automatically after", selection: $store.settings.keyboardCleanTimeout) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                }
                Button(cleaner.active ? "Cleaning…" : "Start cleaning mode") { cleaner.start() }
                    .disabled(cleaner.active)
                Text("The power button and Touch ID can't be blocked by any app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
