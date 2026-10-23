import AppKit
import CoolMenuCore
import SwiftUI

struct MenuView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var clipboard = ClipboardService.shared
    @ObservedObject private var store = SettingsStore.shared
    @Environment(\.openWindow) private var openWindow
    @AppStorage("settingsTab") private var settingsTab = SettingsTab.general.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            PermissionBanner()
            system.sectionTitle("System")
            topProcesses.sectionTitle("Top apps")
            DisplaySliders().sectionTitle("Displays")
            actions.sectionTitle("Tools")
            recentClips.sectionTitle("Recent clipboard")
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { monitor.setConsumer("menu", active: true) }
        .onDisappear { monitor.setConsumer("menu", active: false) }
    }

    private var header: some View {
        HStack {
            Text("CoolMenu").font(.headline)
            Spacer()
            Button { openSettings(.general) } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless)
                .help("Quit CoolMenu")
        }
    }

    private var system: some View {
        VStack(spacing: 8) {
            UsageBar(title: "CPU", value: monitor.cpu, detail: "\(Int((monitor.cpu * 100).rounded()))%")
            Sparkline(values: monitor.cpuHistory).frame(height: 28)
            UsageBar(
                title: "Memory",
                value: Double(monitor.memoryUsed) / Double(max(monitor.memoryTotal, 1)),
                detail: "\(ByteFormat.short(monitor.memoryUsed)) of \(ByteFormat.short(monitor.memoryTotal))"
            )
            UsageBar(
                title: "Disk",
                value: Double(monitor.diskUsed) / Double(max(monitor.diskTotal, 1)),
                detail: "\(ByteFormat.short(monitor.diskTotal - monitor.diskUsed)) free"
            )
        }
    }

    private var topProcesses: some View {
        VStack(spacing: 4) {
            ForEach(monitor.groups.prefix(5)) { group in
                HStack {
                    Text(group.name).lineLimit(1)
                    if group.members.count > 1 {
                        Text("\(group.members.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f%%", group.cpuPercent)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    Text(ByteFormat.short(group.memoryBytes)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.caption)
            }
            if monitor.groups.isEmpty {
                Text("Sampling…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            tool("Clipboard", "doc.on.clipboard", store.settings.clipboardHotKey.displayString) {
                ClipboardPanelController.shared.toggle()
            }
            tool("Tile screen", "rectangle.split.2x2", nil) {
                if let screen = NSScreen.withMouse() { WindowManager.shared.autoLayout(screen) }
            }
            tool("Clean keyboard", "keyboard", nil) { KeyboardCleaner.shared.start() }
            tool("Disk clean", "internaldrive", nil) { openSettings(.monitor) }
            tool("Zones", "rectangle.3.group", nil) { openSettings(.windows) }
            tool("Switcher", "rectangle.stack", store.settings.switcherHotKey.displayString) { openSettings(.switcher) }
        }
    }

    private func tool(_ title: String, _ icon: String, _ shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).frame(width: 16)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if let shortcut { Text(shortcut).font(.caption2.monospaced()).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .font(.caption)
    }

    private var recentClips: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(clipboard.history.items.prefix(4)) { item in
                Button {
                    clipboard.copy(item)
                } label: {
                    HStack {
                        Text(preview(item)).lineLimit(1)
                        Spacer()
                        Text(item.date.formatted(.relative(presentation: .numeric))).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
            if clipboard.history.items.isEmpty {
                Text("Nothing copied yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func preview(_ item: ClipItem) -> String {
        switch item.kind {
        case .text: return item.text?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ") ?? ""
        case .image: return "Image"
        case .files: return item.fileNames.joined(separator: ", ")
        }
    }

    private func openSettings(_ tab: SettingsTab) {
        settingsTab = tab.rawValue
        openWindow(id: SettingsWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
