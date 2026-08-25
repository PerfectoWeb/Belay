import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The pane's last row: Reset with its privacy line, and the two share
/// buttons. Owns the erase confirmation, which offers one last export —
/// erasing is the only destructive act in Settings, and "save it first" is
/// cheaper offered than regretted.
struct StatisticsFooter: View {
    let statistics: UsageStatistics
    var onReset: () -> Void = {}

    @State private var isConfirmingReset = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                // Away from the two it must not be mistaken for, and quiet:
                // a bordered button beside two bordered buttons is a button you
                // click by aiming badly.
                Button("Reset…") { isConfirmingReset = true }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                Text("Numbers stay on this Mac unless you share them.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            CopyStatisticsCardButton(statistics: statistics)
            ShareStatisticsButton(statistics: statistics)
        }
        .alert("Erase your statistics?", isPresented: $isConfirmingReset) {
            Button("Erase", role: .destructive, action: onReset)
            Button("Export…") { exportCSV() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Belay keeps no copy anywhere else.")
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Belay-Statistics.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.csv(for: statistics.days).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// One CSV row per recorded day, oldest first. Plain columns and whole
    /// seconds: the file is for a spreadsheet, not for Belay to read back.
    static func csv(for days: [UsageStatistics.Day]) -> String {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        var lines = ["date,held_seconds,away_seconds,holds,longest_hold_seconds,runs_rescued"]
        for entry in days.sorted(by: { $0.date < $1.date }) {
            lines.append(
                "\(day.string(from: entry.date)),\(Int(entry.heldSeconds)),"
                    + "\(Int(entry.awaySeconds)),\(entry.holds),"
                    + "\(Int(entry.longestHold)),\(entry.rescued)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
