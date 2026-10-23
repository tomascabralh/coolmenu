import Foundation

public enum ClipKind: String, Codable {
    case text
    case image
    case files
}

public struct ClipItem: Codable, Identifiable, Hashable {
    public var id: UUID
    public var date: Date
    public var kind: ClipKind
    public var text: String?
    /// File names (relative to the clips directory) for payloads kept out of the JSON index.
    public var richTextFile: String?
    public var imageFile: String?
    public var filePaths: [String]?
    public var appBundleID: String?
    public var appName: String?
    public var windowTitle: String?
    public var pinned: Bool
    public var contentHash: UInt64

    public init(
        id: UUID = UUID(), date: Date = Date(), kind: ClipKind, text: String? = nil,
        richTextFile: String? = nil, imageFile: String? = nil, filePaths: [String]? = nil,
        appBundleID: String? = nil, appName: String? = nil, windowTitle: String? = nil,
        pinned: Bool = false, contentHash: UInt64
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.text = text
        self.richTextFile = richTextFile
        self.imageFile = imageFile
        self.filePaths = filePaths
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.pinned = pinned
        self.contentHash = contentHash
    }

    public var fileNames: [String] {
        (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
    }

    /// Everything a search can match: content, file names, app name, window title.
    var haystack: String {
        [text ?? "", fileNames.joined(separator: " "), appName ?? "", windowTitle ?? ""]
            .joined(separator: "\n")
    }

    /// Paths of side files this item owns.
    public var storedFiles: [String] {
        [richTextFile, imageFile].compactMap { $0 }
    }
}

public struct ClipHistory: Codable, Equatable {
    public private(set) var items: [ClipItem] = []

    public init(items: [ClipItem] = []) {
        self.items = items
    }

    /// Inserts at the top. A duplicate of existing content moves to the top instead, keeping its pin.
    /// Returns the items evicted so their side files can be removed.
    @discardableResult
    public mutating func insert(_ item: ClipItem, limit: Int) -> [ClipItem] {
        var item = item
        var evicted: [ClipItem] = []
        if let existing = items.firstIndex(where: { $0.contentHash == item.contentHash && $0.kind == item.kind }) {
            item.pinned = items[existing].pinned
            evicted.append(items.remove(at: existing))
        }
        items.insert(item, at: 0)
        evicted += trim(limit: limit)
        // The replaced duplicate's side files are only stale if the new item doesn't reuse them.
        return evicted.filter { old in old.storedFiles.allSatisfy { !item.storedFiles.contains($0) } }
    }

    @discardableResult
    public mutating func trim(limit: Int) -> [ClipItem] {
        guard limit > 0 else { return [] }
        var evicted: [ClipItem] = []
        var kept = 0
        items = items.filter { item in
            if item.pinned { return true }
            kept += 1
            if kept > limit {
                evicted.append(item)
                return false
            }
            return true
        }
        return evicted
    }

    @discardableResult
    public mutating func remove(id: UUID) -> ClipItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    public mutating func togglePin(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
    }

    /// Removes everything except pinned items, returning what was removed.
    public mutating func clearUnpinned() -> [ClipItem] {
        let removed = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        return removed
    }

    /// Pinned first, then most recent. Every whitespace-separated token must match somewhere.
    public func search(_ query: String) -> [ClipItem] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = tokens.isEmpty ? items : items.filter { item in
            let hay = item.haystack.lowercased()
            return tokens.allSatisfy { hay.contains($0) }
        }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }
}

public enum StableHash {
    /// FNV-1a 64-bit. Swift's Hasher is seeded per process, so it can't dedupe across launches.
    public static func fnv1a<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    public static func of(_ string: String) -> UInt64 {
        fnv1a(string.utf8)
    }
}
