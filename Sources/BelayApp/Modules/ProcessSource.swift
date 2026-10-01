import BelayModules
import BelaySupport
import Darwin
import Foundation

/// What the orphan watch reads of the Mac, and the one thing it does to it.
///
/// Names and numbers only. Belay never reads another process's arguments, its
/// environment or its files: the name is `p_comm`, from the same `sysctl` table
/// the rest of the app reads (docs/DISCOVERY.md section 1.1).
protocol ProcessSource: Sendable {
    /// Every process, or `nil` when the table could not be read. Never an
    /// empty list standing in for a failure: that would end every session.
    func table() -> [ProcessSnapshot]?
    /// CPU seconds so far for the pids that can be read, and only those.
    func cpuSeconds(of pids: [pid_t]) -> [pid_t: Double]
    /// Claude Code's live sessions: the pid in each file's name and when the
    /// file was last written. The contents are never opened.
    func sessionRegistry() -> [pid_t: Date]
    /// SIGTERM, once. False when it could not be sent, always so in the App
    /// Store build, whose sandbox lets no signal out.
    func terminate(_ pid: pid_t) -> Bool
}

struct SystemProcesses: ProcessSource {
    /// Where Claude Code keeps its session files and how this build reads
    /// them. A closure, so nothing is resolved before the module is on.
    let claude: @Sendable () -> (access: FileAccessProvider, sessions: URL)

    /// Called from the watcher, which runs on the main actor.
    static let real = SystemProcesses(claude: {
        MainActor.assumeIsolated {
            (
                ClaudeAccess.provider,
                ClaudeAccess.folder.appendingPathComponent("sessions", isDirectory: true)
            )
        }
    })

    func table() -> [ProcessSnapshot]? {
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&request, UInt32(request.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        let stride = MemoryLayout<kinfo_proc>.stride
        // A fork burst between the two calls must not turn into ENOMEM.
        let capacity = size / stride + max(64, size / stride / 4)
        let buffer = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        size = capacity * stride
        guard sysctl(&request, UInt32(request.count), buffer, &size, nil, 0) == 0 else { return nil }
        return (0..<(size / stride)).compactMap { Self.snapshot(of: buffer[$0]) }
    }

    private static func snapshot(of process: kinfo_proc) -> ProcessSnapshot? {
        let pid = process.kp_proc.p_pid
        guard pid > 0 else { return nil }
        let name = withUnsafePointer(to: process.kp_proc.p_comm) { field in
            field.withMemoryRebound(to: CChar.self, capacity: 17) { String(cString: $0) }
        }
        let started = process.kp_proc.p_un.__p_starttime
        return ProcessSnapshot(
            pid: pid, parent: process.kp_eproc.e_ppid, name: name,
            startedAt: Date(
                timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000))
    }

    func cpuSeconds(of pids: [pid_t]) -> [pid_t: Double] {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        guard timebase.denom > 0 else { return [:] }
        // The counters are in mach ticks, which are not nanoseconds on Apple
        // silicon.
        let seconds = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        var found: [pid_t: Double] = [:]
        for pid in pids {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            found[pid] = Double(info.pti_total_user &+ info.pti_total_system) * seconds
        }
        return found
    }

    func sessionRegistry() -> [pid_t: Date] {
        let (access, sessions) = claude()
        let files =
            (try? access.withAccess(to: sessions) { folder in
                try FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles])
            }) ?? []
        var registry: [pid_t: Date] = [:]
        for file in files where file.pathExtension == "json" {
            guard let pid = pid_t(file.deletingPathExtension().lastPathComponent), pid > 0,
                let written = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
            else { continue }
            registry[pid] = written
        }
        return registry
    }

    func terminate(_ pid: pid_t) -> Bool {
        #if BELAY_MAS
        return false
        #else
        return kill(pid, SIGTERM) == 0
        #endif
    }
}
