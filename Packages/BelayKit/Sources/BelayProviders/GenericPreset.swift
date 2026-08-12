import Foundation

/// A pre-filled `GenericTarget`, shipped as data.
///
/// Presets are not code and make no claims: none of the paths below can be
/// verified on this machine (`docs/DISCOVERY` found no `~/.codex`, no aider and
/// no gemini install), and a wrong path costs the user one edit and a
/// "needs setup" badge — never a release. Codex CLI is here rather than in a
/// module of its own for exactly that reason: `PROJECT_STATE` D4 refuses to ship
/// speculative parsing of a format nobody has seen.
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

    public static let all: [GenericPreset] = [
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
            id: "gemini",
            displayName: "Gemini CLI",
            summary: "Watches ~/.gemini, where the CLI keeps its session state.",
            folder: .home(".gemini"),
            processName: "gemini"),
        GenericPreset(
            id: "cline",
            displayName: "Cline",
            summary: """
                Watches Cline's task storage inside VS Code. No process name: the \
                editor stays open long after the agent has stopped working.
                """,
            folder: .home(
                "Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks"),
            processName: nil),
        GenericPreset(
            id: "codex",
            displayName: "Codex CLI",
            summary: """
                Watches ~/.codex/sessions for rollout files. Adjust the folder if \
                your Codex install keeps them elsewhere.
                """,
            folder: .home(".codex/sessions"),
            processName: "codex")
    ]
}
