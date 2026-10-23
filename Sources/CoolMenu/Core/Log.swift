import Foundation

/// Appends to ~/Library/Application Support/CoolMenu/coolmenu.log. The unified log is often
/// unreadable without admin rights, and this one can be attached to a bug report as-is.
enum Log {
    private static let url = AppPaths.support.appendingPathComponent("coolmenu.log")
    private static let queue = DispatchQueue(label: "coolmenu.log")
    private static let maxBytes = 512 * 1024

    static func write(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        queue.async {
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
                try? fm.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
