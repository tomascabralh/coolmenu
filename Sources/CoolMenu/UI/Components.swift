import AppKit
import CoolMenuCore
import SwiftUI

/// Click, then press a shortcut. Global shortcuts are suspended while recording so an existing
/// binding reaches the recorder. Esc cancels; a shortcut needs ⌃, ⌥ or ⌘.
struct KeyRecorder: View {
    @Binding var combo: HotKeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type shortcut…" : combo.displayString)
                .monospaced()
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear { stop() }
        // The local monitor only sees CoolMenu's own keys; leaving the app must not strand every
        // shortcut in the suspended state.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if UInt32(event.keyCode) == KeyCode.escape {
                stop()
                return nil
            }
            let flags = event.modifierFlags
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= HotKeyCombo.command }
            if flags.contains(.option) { modifiers |= HotKeyCombo.option }
            if flags.contains(.control) { modifiers |= HotKeyCombo.control }
            if flags.contains(.shift) { modifiers |= HotKeyCombo.shift }
            combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stop()
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyCenter.shared.resume()
    }
}

struct UsageBar: View {
    let title: String
    let value: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: min(max(value, 0), 1))
                .tint(value > 0.85 ? .red : value > 0.65 ? .orange : .accentColor)
        }
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let points = values.enumerated().map { i, v in
                CGPoint(
                    x: values.count > 1 ? geo.size.width * CGFloat(i) / CGFloat(values.count - 1) : 0,
                    y: geo.size.height * (1 - CGFloat(min(max(v, 0), 1)))
                )
            }
            ZStack {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(Color.accentColor.opacity(0.18))
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    points.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }
}

struct PermissionBanner: View {
    @State private var trusted = AX.isTrusted
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !trusted {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility access needed").font(.callout.weight(.semibold))
                        Text("Required to move windows, paste, switch windows and lock the keyboard.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open System Settings") { AX.openAccessibilitySettings() }.controlSize(.small)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.12)))
            }
        }
        .onReceive(timer) { _ in trusted = AX.isTrusted }
    }
}

struct DisplaySliders: View {
    @ObservedObject var dimming = DimmingService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(dimming.displays) { display in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: display.builtIn ? "laptopcomputer" : "display")
                        Text(display.name).font(.caption)
                        Spacer()
                        Text("\(Int(dimming.level(for: display) * 100))%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "sun.min").font(.caption2)
                        Slider(
                            value: Binding(get: { dimming.level(for: display) }, set: { dimming.setLevel($0, for: display) }),
                            in: DimmingService.minimumLevel...1
                        )
                        Image(systemName: "sun.max").font(.caption2)
                    }
                }
            }
        }
    }
}

extension View {
    func sectionTitle(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            self
        }
    }
}
