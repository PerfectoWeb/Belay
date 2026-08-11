import VigilCore

extension ClaudeCodeProvider {
    /// Split out only to keep the provider file under the length rule; it is one
    /// question — can we read the folder — and it has no other dependencies.
    public var availability: ProviderAvailability {
        guard access.hasAccess(to: configuration.projectsDirectory) else {
            return .needsSetup(
                "Let Vigil read your ~/.claude folder so it can tell when Claude Code is working.")
        }
        return .ready
    }
}
