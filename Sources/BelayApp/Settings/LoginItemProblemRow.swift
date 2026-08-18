import BelaySettings
import SwiftUI

/// The line that appears when macOS has not yet allowed the login item.
///
/// Split out of `GeneralSettingsPane.swift`, which is at the length limit.
struct LoginItemProblemRow: View {
    let problem: LoginItem.Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(problem == .needsApproval ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Login Items…") { LoginItem.openSystemSettings() }
                .controlSize(.small)
        }
    }

    private var message: LocalizedStringKey {
        switch problem {
        case .needsApproval:
            return "macOS is waiting for you to allow this in System Settings."
        case .refused(let reason):
            return "macOS refused the change: \(reason)"
        }
    }
}
