import AppKit
import Combine
import CoolMenuCore
import Darwin

/// CPU, memory, disk and per-app process usage. Samples only while something is showing it.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: UInt64 = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var diskUsed: UInt64 = 0
    @Published private(set) var diskTotal: UInt64 = 0
    @Published private(set) var groups: [ProcessGroup] = []

    private var consumers: Set<String> = []
    private var timer: Timer?
    private var lastTicks: CPUTicks?
    private var lastProcessCPU: [pid_t: UInt64] = [:]
    private var lastSampleTime: UInt64 = 0
    private let queue = DispatchQueue(label: "coolmenu.monitor", qos: .utility)
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    /// Private libSystem call Activity Monitor uses to attribute XPC helpers to their app.
    private let responsiblePid: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    private var cancellable: AnyCancellable?

    func start() {
        cancellable = SettingsStore.shared.observe(\.showCPUInMenuBar)
            .sink { [weak self] show in self?.setConsumer("menubar", active: show) }
    }

    func setConsumer(_ name: String, active: Bool) {
        if active { consumers.insert(name) } else { consumers.remove(name) }
        if consumers.isEmpty {
            timer?.invalidate()
            timer = nil
            // Otherwise the next first sample averages over the whole idle gap.
            queue.async { [weak self] in
                self?.lastTicks = nil
                self?.lastSampleTime = 0
                self?.lastProcessCPU = [:]
            }
        } else if timer == nil {
            sample()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        }
    }

    private func sample() {
        queue.async { [weak self] in
            guard let self else { return }
            let ticks = Self.cpuTicks()
            var cpuValue = 0.0
            if let previous = lastTicks, let ticks { cpuValue = CPUTicks.usage(from: previous, to: ticks) }
            lastTicks = ticks
            let memory = Self.memoryUsed()
            let disk = Self.disk()
            let processGroups = sampleProcesses()
            DispatchQueue.main.async {
                self.cpu = cpuValue
                self.cpuHistory = Array((self.cpuHistory + [cpuValue]).suffix(60))
                self.memoryUsed = memory
                self.diskUsed = disk.used
                self.diskTotal = disk.total
                self.groups = processGroups
            }
        }
    }

    // MARK: System totals

    private static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    /// Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private static func disk() -> (used: UInt64, total: UInt64) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return (0, 0) }
        return (UInt64(total) - UInt64(free), UInt64(total))
    }

    // MARK: Processes

    /// Own-user processes only: reading other users' tasks needs root.
    private func sampleProcesses() -> [ProcessGroup] {
        let now = mach_absolute_time()
        let elapsedNs = Double((now - lastSampleTime) * timebase.numer / timebase.denom)
        let firstSample = lastSampleTime == 0
        lastSampleTime = now

        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) * 2)
        let found = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))

        var samples: [ProcessSample] = []
        var cpuTimes: [pid_t: UInt64] = [:]
        for pid in pids.prefix(max(found, 0)) where pid > 0 {
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize else { continue }
            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { continue }

            let cpuNs = (task.pti_total_user + task.pti_total_system) * timebase.numer / timebase.denom
            cpuTimes[pid] = cpuNs
            let previous = lastProcessCPU[pid] ?? cpuNs
            let percent = firstSample || elapsedNs <= 0 ? 0 : Double(cpuNs &- previous) / elapsedNs * 100

            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)

            samples.append(ProcessSample(
                pid: pid,
                ppid: Int32(bsd.pbi_ppid),
                responsiblePid: responsiblePid?(pid) ?? 0,
                name: name.isEmpty ? "pid \(pid)" : name,
                cpuPercent: max(percent, 0),
                memoryBytes: Self.footprint(pid) ?? task.pti_resident_size
            ))
        }
        lastProcessCPU = cpuTimes

        var roots: Set<Int32> = []
        var names: [Int32: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            roots.insert(app.processIdentifier)
            names[app.processIdentifier] = app.localizedName
        }
        return ProcessGrouper.group(samples, appRoots: roots, appNames: names)
    }

    private static func footprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }
}
