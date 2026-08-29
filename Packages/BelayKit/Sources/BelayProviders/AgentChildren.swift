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
/// `.working` heartbeat forever and overrides Tier A's idle rule. Belay then
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
/// unbounded hold nobody can explain is the worse of the two failures. For a
/// user who has turned Precise Detection on, the open tool-call bracket in
/// `SessionState` covers that case exactly instead of approximately.
///
/// ## Why the whole tree
///
/// Direct children alone missed the common shape. Claude Code runs its Bash
/// tool inside one shell that lives for the whole session, so the shell is an
/// old direct child and the thing actually doing the work — `node`, `pytest`,
/// `swift`, the compiler it forks in turn — is a grandchild or deeper. Every
/// worker a test runner spawns is evidence of the same tool call, and looking
/// one level down saw none of them. The descendants are walked from the agent
/// down rather than by scanning upward from each process, which keeps the cost
/// proportional to the agent's own tree and not to the machine's.
enum AgentChildren {
    /// How deep the walk goes before it stops looking.
    ///
    /// Deep enough for a real tool call — shell, runner, worker, compiler, the
    /// thing the compiler forks — and shallow enough that a pid table mangled
    /// by pid reuse into a cycle cannot cost anything. The visited set already
    /// makes cycles terminate; this bounds the work as well.
    private static let maxDepth = 8

    /// Pids from `pids` with at least one descendant started within `maxAge`.
    ///
    /// One `sysctl` for the whole table rather than one call per pid: the sweep
    /// runs every 15 s and the process list is read once anyway.
    static func busy(among pids: Set<pid_t>, youngerThan maxAge: TimeInterval, now: Date) -> Set<pid_t>? {
        guard !pids.isEmpty, let children = childTable() else { return nil }
        let cutoff = now.addingTimeInterval(-maxAge)
        var byParent: [pid_t: [Child]] = [:]
        for child in children {
            byParent[child.parent, default: []].append(child)
        }
        var busy: Set<pid_t> = []
        for pid in pids where hasYoungDescendant(of: pid, in: byParent, after: cutoff) {
            busy.insert(pid)
        }
        return busy
    }

    /// Breadth-first, so the shallow answer — a tool that just started — is
    /// found without walking a long-lived server's subtree first.
    private static func hasYoungDescendant(
        of pid: pid_t, in byParent: [pid_t: [Child]], after cutoff: Date
    ) -> Bool {
        var frontier = [pid]
        var visited: Set<pid_t> = [pid]
        var depth = 0
        while !frontier.isEmpty, depth < maxDepth {
            var next: [pid_t] = []
            for parent in frontier {
                for child in byParent[parent] ?? [] {
                    if child.startedAt > cutoff { return true }
                    if visited.insert(child.pid).inserted { next.append(child.pid) }
                }
            }
            frontier = next
            depth += 1
        }
        return false
    }

    /// How many processes sit under `pid`, at any depth. Only the tests use
    /// this, to tell "the probe found nothing" apart from "there was nothing to
    /// find" — a shell that execs in place leaves no second level at all.
    static func descendantCount(of pid: pid_t) -> Int {
        guard let children = childTable() else { return 0 }
        var byParent: [pid_t: [Child]] = [:]
        for child in children { byParent[child.parent, default: []].append(child) }
        var frontier = [pid]
        var visited: Set<pid_t> = [pid]
        var total = 0
        while !frontier.isEmpty {
            var next: [pid_t] = []
            for parent in frontier {
                for child in byParent[parent] ?? [] where visited.insert(child.pid).inserted {
                    total += 1
                    next.append(child.pid)
                }
            }
            frontier = next
        }
        return total
    }

    private struct Child {
        let pid: pid_t
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
        // A quarter extra on top of the size query, not a fixed handful: the
        // table grows between the two calls, and a fork burst — a parallel
        // build fanning out, the moment this probe matters most — can add
        // more than a few entries in that window. ENOMEM here costs a whole
        // 15-second tick of busy information.
        let capacity = size / stride + max(64, size / stride / 4)
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
            children.append(
                Child(
                    pid: process.kp_proc.p_pid, parent: parent,
                    startedAt: startTime(of: process)))
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
