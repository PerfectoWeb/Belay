import BelayModules
import SwiftUI

extension AppDelegate {
    /// What Orphan Watch needs from the rest of the app: which agents are on,
    /// which are working, somewhere to say something, and where a click goes.
    func wireOrphanWatch(_ controller: BelayController, _ settingsWindow: SettingsWindow) {
        let orphans = appState.modules.orphans
        orphans.agentIsOn = { [weak settings] agent in
            settings?.isEnabled(agent == .codex ? .codex : .claudeCode) ?? true
        }
        orphans.workingAgents = { [weak appState] in
            guard let snapshot = appState?.snapshot else { return [] }
            var working: Set<OrphanAgent> = []
            for session in snapshot.sessions where snapshot.activities[session.id] == .working {
                switch session.provider {
                case .claudeCode: working.insert(.claude)
                case .codex: working.insert(.codex)
                default: break
                }
            }
            return working
        }
        orphans.notify = { [weak controller] count in
            Task { await controller?.notifier.leftBehind(count: count) }
        }
        NotificationClicks.onOrphans = { [weak settingsWindow] in
            settingsWindow?.show(pane: .modules)
        }
    }
}
