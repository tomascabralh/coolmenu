import Foundation

public struct ProcessSample: Hashable, Identifiable {
    public var pid: Int32
    public var ppid: Int32
    /// The process macOS attributes this one to (an app for its XPC helpers), or 0 if unknown.
    public var responsiblePid: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public var id: Int32 { pid }

    public init(pid: Int32, ppid: Int32, responsiblePid: Int32 = 0, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.ppid = ppid
        self.responsiblePid = responsiblePid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct ProcessGroup: Identifiable, Hashable {
    public var id: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    /// Every member including the root, heaviest CPU first.
    public var members: [ProcessSample]
}

public enum ProcessGrouper {
    /// Groups helper and child processes under their logical parent and aggregates their usage.
    /// The parent is the nearest app in `appRoots`; failing that, the responsible process; failing
    /// that, the topmost ancestor below launchd.
    public static func group(_ samples: [ProcessSample], appRoots: Set<Int32>, appNames: [Int32: String] = [:]) -> [ProcessGroup] {
        var byPid: [Int32: ProcessSample] = [:]
        for s in samples { byPid[s.pid] = s }

        func root(of sample: ProcessSample) -> Int32 {
            var current = sample
            var seen: Set<Int32> = [sample.pid]
            while true {
                if appRoots.contains(current.pid) { return current.pid }
                guard current.ppid > 1, let parent = byPid[current.ppid], !seen.contains(parent.pid) else { break }
                seen.insert(parent.pid)
                current = parent
            }
            if sample.responsiblePid > 0, sample.responsiblePid != sample.pid, byPid[sample.responsiblePid] != nil {
                return sample.responsiblePid
            }
            return current.pid
        }

        var members: [Int32: [ProcessSample]] = [:]
        for s in samples { members[root(of: s), default: []].append(s) }

        return members.map { rootPid, list in
            ProcessGroup(
                id: rootPid,
                name: appNames[rootPid] ?? byPid[rootPid]?.name ?? "pid \(rootPid)",
                cpuPercent: list.reduce(0) { $0 + $1.cpuPercent },
                memoryBytes: list.reduce(0) { $0 + $1.memoryBytes },
                members: list.sorted { $0.cpuPercent > $1.cpuPercent }
            )
        }
        .sorted { ($0.cpuPercent, $0.memoryBytes) > ($1.cpuPercent, $1.memoryBytes) }
    }
}

public struct CPUTicks: Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// Busy fraction (0...1) between two samples.
    public static func usage(from prev: CPUTicks, to cur: CPUTicks) -> Double {
        let busy = Double((cur.user &- prev.user) &+ (cur.system &- prev.system) &+ (cur.nice &- prev.nice))
        let total = busy + Double(cur.idle &- prev.idle)
        return total > 0 ? busy / total : 0
    }
}

public enum ByteFormat {
    public static func short(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}
