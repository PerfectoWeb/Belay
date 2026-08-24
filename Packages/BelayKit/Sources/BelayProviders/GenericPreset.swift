import Foundation

/// A pre-filled `GenericTarget`, shipped as data.
///
/// Presets are not code and make no claims: a wrong path costs the user one
/// edit and a "needs setup" badge — never a release. `PROJECT_STATE` D4 kept
/// Codex CLI in this list for a year for exactly that reason; it graduated to
/// `CodexProvider` the day its rollout format was verified on a real install.
public struct GenericPreset: Sendable, Equatable, Identifiable {
    /// Where the preset expects the agent's working files to be.
    public enum Folder: Sendable, Equatable {
        /// A fixed path relative to the user's home directory.
        case home(String)
        /// The preset cannot know the path — the agent writes into whichever
        /// project you run it in. The UI asks for it with this prompt.
        case userPicked(String)
    }

    public let id: String
    public let displayName: String
    public let summary: String
    public let folder: Folder
    public let processName: String?

    /// The prompt for an open panel, or `nil` if the preset fills the path in.
    public var folderPrompt: String? {
        guard case .userPicked(let prompt) = folder else { return nil }
        return prompt
    }

    public func target(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        folder pickedFolder: URL? = nil
    ) -> GenericTarget {
        let watched: URL? =
            switch folder {
            case .home(let relative): home.appendingPathComponent(relative, isDirectory: true)
            case .userPicked: pickedFolder
            }
        return GenericTarget(
            displayName: displayName,
            watchedFolder: watched,
            processName: processName,
            webhookIdentifier: id)
    }
}

extension GenericPreset {
    /// Adding a preset is adding one element to this array. No new type, no new
    /// file, no UI change — that is the whole point of the generic provider.
    /// The preset whose name is the one given, if any.
    ///
    /// Matched on the display name with case and spacing removed, and on the id
    /// as well, because "Gemini CLI", "gemini cli" and "gemini" are all the same
    /// answer. Nothing fuzzier than that: a row wearing the wrong vendor's mark
    /// is worse than a row wearing none.
    public static func matching(name: String) -> GenericPreset? {
        func flattened(_ text: String) -> String {
            text.lowercased().filter { !$0.isWhitespace }
        }
        let wanted = flattened(name)
        return all.first { flattened($0.displayName) == wanted || $0.id == wanted }
    }

    /// The menu shows this order: the big CLIs first, then the rest. Codex is
    /// deliberately absent: it has a first-class provider now, and a preset
    /// row beside it would report every session twice.
    public static let all: [GenericPreset] = [
        GenericPreset(
            id: "gemini",
            displayName: "Gemini CLI",
            summary: "Watches ~/.gemini, where the CLI keeps its session state.",
            folder: .home(".gemini"),
            processName: "gemini"),
        // Verified on a real install: session-state/<uuid>/events.jsonl is an
        // append-only stream with explicit turn_start/turn_end events, flushed
        // during the turn, not after it. The CLI ships its own hook system,
        // so an exact integration has somewhere to grow from this preset.
        GenericPreset(
            id: "copilot",
            displayName: "Copilot CLI",
            summary: """
                Watches ~/.copilot/session-state, where Copilot CLI streams \
                its session events.
                """,
            folder: .home(".copilot/session-state"),
            processName: "copilot"),
        // OpenCode keeps everything in one SQLite database whose WAL sits at
        // the root of this folder; writes land there at every tool call and
        // message boundary while a turn runs. The log/ subfolder also churns
        // while the app is merely open, which the process filter and the
        // idle window absorb.
        GenericPreset(
            id: "opencode",
            displayName: "OpenCode",
            summary: "Watches ~/.local/share/opencode, where OpenCode keeps its sessions.",
            folder: .home(".local/share/opencode"),
            processName: "opencode"),
        GenericPreset(
            id: "aider",
            displayName: "Aider",
            summary: """
                Aider writes its chat and input history into the project it is \
                running in, so point Belay at that folder.
                """,
            folder: .userPicked("Choose the project folder you run Aider in"),
            processName: "aider"),
        GenericPreset(
            id: "cline",
            displayName: "Cline (VS Code)",
            summary: """
                Watches Cline's task storage inside VS Code. No process name: the \
                editor stays open long after the agent has stopped working. The \
                Cline CLI needs no tile: it is built in above.
                """,
            folder: .home(
                "Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks"),
            processName: nil),
        // Asked for in issue #3 by somebody already running Pi through the
        // generic provider with exactly these values, which is better
        // evidence than any preset above shipped with.
        GenericPreset(
            id: "pi",
            displayName: "Pi",
            summary: "Watches ~/.pi/agent/sessions, where Pi keeps its session files.",
            folder: .home(".pi/agent/sessions"),
            processName: "pi")
    ]
}
