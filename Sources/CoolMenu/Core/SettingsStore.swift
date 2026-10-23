import Combine
import CoolMenuCore
import Foundation

enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CoolMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let clips: URL = {
        let dir = support.appendingPathComponent("clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// Persists AppSettings as JSON in Application Support. Local only; nothing leaves the Mac.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings

    private let url = AppPaths.support.appendingPathComponent("settings.json")
    private var saveCancellable: AnyCancellable?

    private init() {
        if let data = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                settings = decoded
            } else {
                // Not JSON at all: keep a copy instead of letting the next save overwrite it.
                try? data.write(to: url.deletingPathExtension().appendingPathExtension("unreadable.json"))
                settings = AppSettings()
            }
        } else {
            settings = AppSettings()
        }
        saveCancellable = $settings
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.flush() }
    }

    /// Writes settings now. Called by the debounced save and on quit.
    func flush() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(settings).write(to: url, options: .atomic)
    }

    /// Emits (debounced) whenever the projection changes, starting with the current value.
    func observe<T: Equatable>(_ keyPath: KeyPath<AppSettings, T>) -> AnyPublisher<T, Never> {
        $settings
            .map(keyPath)
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
