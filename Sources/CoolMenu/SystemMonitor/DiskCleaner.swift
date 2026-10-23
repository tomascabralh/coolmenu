import AppKit

/// Finds regenerable clutter and moves it to the Trash, never deleting outright, so every clean
/// can be undone from Finder until the Trash is emptied.
final class DiskCleaner: ObservableObject {
    static let shared = DiskCleaner()

    struct Target: Identifiable {
        let id: String
        let name: String
        let detail: String
        let url: URL
        var size: Int64?
        var exists: Bool
    }

    @Published private(set) var targets: [Target]
    @Published private(set) var scanning = false
    @Published private(set) var lastResult: String?
    @Published private(set) var cleaning = false
    private var rescanQueued = false

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func target(_ id: String, _ name: String, _ detail: String, _ path: String) -> Target {
            Target(id: id, name: name, detail: detail, url: home.appendingPathComponent(path), size: nil, exists: false)
        }
        targets = [
            target("caches", "App caches", "~/Library/Caches. Apps rebuild these as needed.", "Library/Caches"),
            target("logs", "Logs", "~/Library/Logs", "Library/Logs"),
            target("derived", "Xcode DerivedData", "Build products Xcode regenerates.", "Library/Developer/Xcode/DerivedData"),
            target("simcaches", "Simulator caches", "CoreSimulator caches.", "Library/Developer/CoreSimulator/Caches"),
            target("npm", "npm cache", "~/.npm/_cacache", ".npm/_cacache"),
            target("pnpm", "pnpm store", "Shared pnpm package store.", "Library/pnpm/store"),
            target("gradle", "Gradle caches", "~/.gradle/caches", ".gradle/caches"),
        ]
    }

    var totalSize: Int64 { targets.compactMap(\.size).reduce(0, +) }

    func scan() {
        guard !scanning else {
            rescanQueued = true
            return
        }
        scanning = true
        let snapshot = targets
        DispatchQueue.global(qos: .utility).async {
            let scanned = snapshot.map { target -> Target in
                var t = target
                t.exists = FileManager.default.fileExists(atPath: target.url.path)
                t.size = t.exists ? Self.allocatedSize(of: target.url) : 0
                return t
            }
            DispatchQueue.main.async {
                self.targets = scanned
                self.scanning = false
                if self.rescanQueued {
                    self.rescanQueued = false
                    self.scan()
                }
            }
        }
    }

    /// Moves the folder's contents (not the folder itself) to the Trash. Items in use or protected
    /// by macOS are skipped.
    func clean(_ target: Target) {
        guard !cleaning else { return }
        cleaning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let children = (try? fm.contentsOfDirectory(at: target.url, includingPropertiesForKeys: nil)) ?? []
            var moved = 0
            var skipped = 0
            for child in children where !child.lastPathComponent.hasPrefix("com.coolmenu") {
                do {
                    try fm.trashItem(at: child, resultingItemURL: nil)
                    moved += 1
                } catch {
                    skipped += 1
                }
            }
            DispatchQueue.main.async {
                self.cleaning = false
                self.lastResult = "\(target.name): moved \(moved) item(s) to the Trash"
                    + (skipped > 0 ? ", skipped \(skipped) in use or protected" : "")
                self.scan()
            }
        }
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
