import AppKit
import Combine
import CoolMenuCore
import SwiftUI

final class ClipboardPanelController: ObservableObject {
    static let shared = ClipboardPanelController()

    @Published var query = ""
    @Published var selection = 0

    private let service = ClipboardService.shared
    private var cancellables: Set<AnyCancellable> = []
    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(size: NSSize(width: 620, height: 460)) {
            ClipboardPanelView(controller: self, service: self.service)
        }
        return panel
    }()

    var results: [ClipItem] { service.history.search(query) }

    func start() {
        SettingsStore.shared.observe(\.clipboardHotKey)
            .sink { combo in
                HotKeyCenter.shared.unregister(group: "clipboard")
                HotKeyCenter.shared.register(group: "clipboard", combo) { ClipboardPanelController.shared.toggle() }
            }
            .store(in: &cancellables)
        $query
            .sink { [weak self] _ in self?.selection = 0 }
            .store(in: &cancellables)
    }

    func toggle() {
        if panel.isVisible { return panel.dismiss() }
        query = ""
        selection = 0
        panel.present { [weak self] event in self?.handle(event) ?? event }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else { return event }
        let items = results
        let command = event.modifierFlags.contains(.command)
        switch UInt32(event.keyCode) {
        case KeyCode.escape:
            panel.dismiss()
        case KeyCode.down:
            selection = min(selection + 1, max(items.count - 1, 0))
        case KeyCode.up:
            selection = max(selection - 1, 0)
        case KeyCode.returnKey:
            if items.indices.contains(selection) {
                paste(items[selection], plainText: event.modifierFlags.contains(.shift))
            }
        case 35 where command: // ⌘P
            if items.indices.contains(selection) { service.togglePin(items[selection]) }
        case KeyCode.delete where command:
            if items.indices.contains(selection) {
                service.delete(items[selection])
                selection = min(selection, max(results.count - 1, 0))
            }
        default:
            // ⌘1...⌘9 paste the nth visible item directly.
            // Key codes, not characters: with ⇧ held the characters are "!", "@", ...
            if command, let digit = Self.digitKeyCodes[event.keyCode], items.indices.contains(digit - 1) {
                paste(items[digit - 1], plainText: event.modifierFlags.contains(.shift))
                return nil
            }
            return event
        }
        return nil
    }

    private static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    func paste(_ item: ClipItem, plainText: Bool) {
        panel.dismiss()
        service.paste(item, plainText: plainText)
    }
}

struct ClipboardPanelView: View {
    @ObservedObject var controller: ClipboardPanelController
    @ObservedObject var service: ClipboardService
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = controller.results
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard: text, app, window or file name", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)
                Text("\(items.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(14)
            Divider()
            if items.isEmpty {
                ContentUnavailableView(
                    controller.query.isEmpty ? "Nothing copied yet" : "No matches",
                    systemImage: "doc.on.clipboard"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ClipRow(item: item, index: index, selected: index == controller.selection, service: service)
                                    .id(item.id)
                                    .onTapGesture { controller.paste(item, plainText: false) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: controller.selection) { _, newValue in
                        if items.indices.contains(newValue) { proxy.scrollTo(items[newValue].id) }
                    }
                }
            }
            Divider()
            HStack(spacing: 14) {
                hint("↩", "Paste")
                hint("⇧↩", "Plain text")
                hint("⌘1–9", "Quick paste")
                hint("⌘P", "Pin")
                hint("⌘⌫", "Delete")
                Spacer()
                if !AX.isTrusted {
                    Label("Grant Accessibility to paste", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 620, height: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { searchFocused = true }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.caption.monospaced()).padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let service: ClipboardService

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIcon(bundleID: item.appBundleID).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                content
                HStack(spacing: 6) {
                    if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                    Text(meta).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if index < 9 {
                Text("⌘\(index + 1)").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.22) : .clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text:
            Text(item.text ?? "").lineLimit(3).font(.system(size: 13))
        case .image:
            if let image = service.image(for: item) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 80, alignment: .leading)
            } else {
                Text("Image").italic()
            }
        case .files:
            Label(item.fileNames.joined(separator: ", "), systemImage: "doc").lineLimit(2)
        }
    }

    private var meta: String {
        let parts = [item.appName, item.windowTitle, item.date.formatted(.relative(presentation: .named))]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct AppIcon: View {
    let bundleID: String?

    var body: some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
        }
    }
}
