import BelaySupport
import Foundation

/// Waiting for Claude Code to be used for the first time.
///
/// Split out of `BelayController` only to keep that file under the length rule.
extension BelayController {
    /// `~/.claude/projects` does not exist until Claude Code opens its first
    /// project, and a new user installs Belay before that happens. Without this
    /// the provider stays stopped until the app is relaunched, which nobody has
    /// any reason to guess at. Thirty seconds, and it stops as soon as it takes.
    func watchForClaudeCodeAppearing() {
        tasks.append(
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard let self, !Task.isCancelled else { return }
                    guard await self.providers.claudeCodeIsWaiting else { return }
                    await self.providers.retryStart()
                    await self.publishProviderStatus()
                }
            }
        )
    }

}
