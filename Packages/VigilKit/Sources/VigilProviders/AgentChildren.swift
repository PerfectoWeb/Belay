import Darwin
import Foundation

/// Whether an agent process currently has a child running.
///
/// This closes the gap `docs/11` calls **R6**: a long tool call — or a task the
/// agent backgrounded and is waiting on — produces no transcript growth, so
/// after `inferredIdleAfter` Tier A concludes the turn is over and the Mac is
/// allowed to sleep out from under a job that is very much still going.
///
/// Observed on this machine, which is what motivated it: a session whose last
/// transcript record was `end_turn` eight minutes earlier still had a live
/// `/bin/zsh` child running for 8m46s — the build it was waiting on. Its sibling
/// session, genuinely idle, had no children at all.
///
/// A child is evidence of *the agent's own work*, not merely of the agent
/// existing, which is why this is allowed to mean "working" where plain process
/// presence is not (`docs/03` Tier C).
enum AgentChildren {
    /// Pids that have at least one live child, out of `pids`.
    ///
    /// One `sysctl` for the whole table rather than one call per pid: the sweep
    /// runs every 15 s and the process list is read once anyway.
    static func busy(among pids: Set<pid_t>) -> Set<pid_t>? {
        guard !pids.isEmpty, let parents = parentTable() else { return nil }
        return Set(parents.filter { pids.contains($0.value) }.map(\.value))
    }

    /// child pid -> parent pid, for every process on the machine.
    private static func parentTable() -> [pid_t: pid_t]? {
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&request, UInt32(request.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        let stride = MemoryLayout<kinfo_proc>.stride
        let capacity = size / stride + 8
        let buffer = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        size = capacity * stride
        guard sysctl(&request, UInt32(request.count), buffer, &size, nil, 0) == 0 else {
            // A failed read must mean "ask again later", never "nothing is
            // running" — the latter would drop the assertion mid-turn.
            return nil
        }

        var table: [pid_t: pid_t] = [:]
        for index in 0..<(size / stride) {
            let process = buffer[index]
            let pid = process.kp_proc.p_pid
            let parent = process.kp_eproc.e_ppid
            guard pid > 0, parent > 0 else { continue }
            table[pid] = parent
        }
        return table
    }
}
