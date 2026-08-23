import BelayCore
import Foundation

extension ClaudeCodeProvider {
    /// Split out only to keep the provider file under the length rule; it is one
    /// question — can we read the folder — and it has no other dependencies.
    public var availability: ProviderAvailability {
        switch reach {
        case .ready:
            return .ready
        case .notInstalled:
            // Not a permission problem either, and the worst thing to say
            // about it is "allow access": there is nothing to allow.
            return .unavailable(
                String(localized: "Claude Code is not installed on this Mac.", bundle: .main))
        case .noProjectsYet:
            // Not a permission problem, and offering a grant button here is
            // what sent people round the loop: they grant `~/.claude`, the
            // subdirectory still is not there, and the app asks again.
            return .unavailable(
                String(
                    localized: """
                        Claude Code has not opened a project on this Mac yet. Belay starts \
                        watching by itself when it does.
                        """, bundle: .main))
        case .noAccess:
            return .needsSetup(
                String(
                    localized:
                        "Let Belay read your ~/.claude folder so it can tell when Claude Code is working.",
                    bundle: .main))
        }
    }

    /// How far into `~/.claude` this build can currently see.
    ///
    /// The three cases were one for a long time, and the one they were was
    /// "no access" — so a Mac where Claude Code had never opened a project was
    /// told to grant a folder it had already granted. `projects` does not exist
    /// until the first session in a directory, which is the state every new
    /// user is in.
    enum Reach {
        case ready
        case notInstalled
        case noProjectsYet
        case noAccess
    }

    var reach: Reach {
        if access.isKnownMissing(configuration.projectsDirectory.deletingLastPathComponent()) {
            return .notInstalled
        }
        if access.hasAccess(to: configuration.projectsDirectory) { return .ready }
        // The parent is reachable, so nothing is being withheld: the folder
        // simply is not there yet.
        if access.hasAccess(to: configuration.projectsDirectory.deletingLastPathComponent()) {
            return .noProjectsYet
        }
        return .noAccess
    }
}
