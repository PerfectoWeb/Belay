import Darwin
import Foundation

/// Whether an agent process has *recently started* a child.
///
/// This closes the gap `docs/11` calls **R6**: a long tool call — or a task the
/// agent backgrounded and is waiting on — produces no transcript growth, so
/// after `inferredIdleAfter` Tier A concludes the turn is over and the Mac is
/// allowed to sleep out from under a job that is very much still going.
///
/// A child is evidence of *the agent's own work*, not merely of the agent
/// existing, which is why this is allowed to mean "working" where plain process
/// presence is not (`docs/03` Tier C).
///
/// ## Why the age bound
///
/// "Has a child" alone is unbounded: a stdio MCP server, a dev server the agent
/// started, an `npm run dev` a Bash call left in the background — each is a
/// direct child that outlives every turn, so the 15 s sweep turns it into a
/// `.working` heartbeat forever and overrides Tier A's idle rule. Vigil then
/// pins the Mac awake next to a genuinely idle agent until the max-duration cap
/// trips, with nothing in the UI a user could trace back to a cause.
///
/// So only a child younger than the caller's idle horizon counts: the claim
/// becomes "the agent spawned something recently", which is what work looks
/// like, rather than "the agent once spawned something". Start times come from
/// the same `sysctl` snapshot as the parent links, so this costs one extra
/// field and no extra syscall. The alternative — requiring the child *set* to
/// change between sweeps — needs per-sweep state, misses nothing this does not,
/// and re-arms on a child *exiting*, which is the opposite of work starting.
///
/// The two horizons compound, and that is deliberate. This one counts a child
/// for `maxAge` after it starts; the idle sweep then waits another
/// `inferredIdleAfter` from the last tick that saw one. A single short-lived
/// child therefore extends the tail to roughly twice the horizon plus the
/// coordinator's grace, not once. Bounded, in the safe direction, and worth
/// knowing before reading either number as "the" bound.
///
/// The honest cost: a single silent child that runs for longer than the horizon
/// (the 8m46s `/bin/zsh` build in `docs/DISCOVERY`) stops counting once it ages
/// out, so Tier C no longer extends the tail indefinitely for it. That is the
/// intended trade — invariant 4 says the assertion is always released, and an
/// unbounded hold nobody can explain is the worse of the two failures.
enum AgentChildren {
    /// Pids from `pids` that have at least one child started within `maxAge`.
    ///
    /// One `sysctl` for the whole table rather than one call per pid: the sweep
    /// runs every 15 s and the process list is read once anyway.
    static func busy(among pids: Set<pid_t>, youngerThan maxAge: TimeInterval, now: Date) -> Set<pid_t>? {
        guard !pids.isEmpty, let children = childTable() else { return nil }
        let cutoff = now.addingTimeInterval(-maxAge)
        var busy: Set<pid_t> = []
        for child in children where pids.contains(child.parent) && child.startedAt > cutoff {
            busy.insert(child.parent)
        }
        return busy
    }

    private struct Child {
        let parent: pid_t
        let startedAt: Date
    }

    /// Every process on the machine, as (parent, start time).
    private static func childTable() -> [Child]? {
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

        var children: [Child] = []
        children.reserveCapacity(size / stride)
        for index in 0..<(size / stride) {
            let process = buffer[index]
            let parent = process.kp_eproc.e_ppid
            guard process.kp_proc.p_pid > 0, parent > 0 else { continue }
            children.append(Child(parent: parent, startedAt: startTime(of: process)))
        }
        return children
    }

    /// `p_starttime` is wall-clock, from the same source as `Date`. A clock that
    /// jumped backwards makes a child look newer than it is, which errs towards
    /// staying awake — the safe direction.
    private static func startTime(of process: kinfo_proc) -> Date {
        let started = process.kp_proc.p_un.__p_starttime
        return Date(
            timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
    }
}
