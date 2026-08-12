import Darwin
import Foundation

/// Which of the current user's processes are running, by name.
///
/// `ProcessPresence` answers the same question for Claude Code, but it can start
/// from `~/.claude/sessions/<pid>.json` and go straight to a pid. A generic
/// target has only a name the user typed, so this enumerates the user's own
/// processes with `sysctl(KERN_PROC_UID)` and reads `p_comm` — the short command
/// name that comes back in `kinfo_proc` itself.
///
/// It deliberately stops there. `docs/03` Tier C warns that `KERN_PROCARGS2` may
/// be restricted under the sandbox, and `docs/DISCOVERY` §1.1 records the
/// decision not to inspect other processes' argument vectors at all — reading
/// another process's command line is both unnecessary here and the kind of thing
/// that should make App Review stop and look.
///
/// The roster is context only. Nothing in this file can produce `.working`.
enum ProcessRoster {
    /// `p_comm` is `MAXCOMLEN` bytes: names longer than this arrive truncated,
    /// so a configured name is matched against its own truncation too.
    static let commandNameLimit = 16

    /// Lowercased `p_comm` values for every process owned by `uid`, or `nil` if
    /// `sysctl` would not answer.
    ///
    /// The distinction matters: an empty set says "your agent is not running"
    /// and ends sessions, while `nil` says "ask again later". Treating a failed
    /// syscall as an empty process table would drop the assertion mid-turn.
    static func scan(uid: uid_t = getuid()) -> Set<String>? {
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(uid)]
        var byteCount = 0
        guard sysctl(&request, u_int(request.count), nil, &byteCount, nil, 0) == 0, byteCount > 0
        else { return nil }

        let stride = MemoryLayout<kinfo_proc>.stride
        // Headroom: processes can appear between sizing and reading, and a short
        // buffer makes the second call fail outright with ENOMEM.
        let capacity = byteCount / stride + 32
        let buffer = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        var readCount = capacity * stride
        guard sysctl(&request, u_int(request.count), buffer, &readCount, nil, 0) == 0
        else { return nil }

        var names: Set<String> = []
        for index in 0..<(readCount / stride) {
            let name = withUnsafePointer(to: buffer[index].kp_proc.p_comm) { field in
                field.withMemoryRebound(to: CChar.self, capacity: commandNameLimit + 1) {
                    String(cString: $0)
                }
            }
            guard !name.isEmpty else { continue }
            names.insert(name.lowercased())
        }
        return names
    }

    static func contains(_ name: String, in roster: Set<String>) -> Bool {
        let wanted = name.lowercased()
        guard !wanted.isEmpty else { return false }
        return roster.contains(wanted) || roster.contains(String(wanted.prefix(commandNameLimit)))
    }
}
