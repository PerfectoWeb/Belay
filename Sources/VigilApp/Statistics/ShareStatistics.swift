import AppKit
import SwiftUI

/// Opens the system share sheet with the card, the sentence and the link.
///
/// The card goes first because that is what a share extension previews; the
/// sentence and the URL ride along so anything that cannot show an image — Mail's
/// plain-text composer, a paste into a terminal — still says something true and
/// still points home.
struct ShareStatisticsButton: View {
    let statistics: UsageStatistics

    var body: some View {
        Button {
            present()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Shares a card, a summary and a link to Vigil")
    }

    private func present() {
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        let picker = NSSharingServicePicker(items: ShareStatistics.sharingItems(from: statistics))
        let rect = NSRect(x: view.bounds.midX, y: view.bounds.minY + 40, width: 1, height: 1)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }
}

/// The share sheet is one click too many for "put it in the thread I already
/// have open", which is what most people actually want to do with this.
struct CopyStatisticsCardButton: View {
    let statistics: UsageStatistics
    @State private var copied = false

    var body: some View {
        Button {
            ShareStatistics.copy(statistics)
            confirm()
        } label: {
            Label(
                copied ? "Copied" : "Copy card and link",
                systemImage: copied ? "checkmark" : "doc.on.doc"
            )
            .font(.system(size: 12, weight: .medium))
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Copies the card image and the summary text together")
    }

    /// A copy button with no acknowledgement leaves the user clicking it twice.
    /// The task only flips a label back, so losing it on a closing panel costs
    /// nothing.
    private func confirm() {
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

enum ShareStatistics {
    static func items(from statistics: UsageStatistics) -> [Any] {
        var items: [Any] = [summary(statistics)]
        if let url = Branding.repositoryURL { items.append(url) }
        return items
    }

    /// The card in front, then whatever `items` carries.
    @MainActor
    static func sharingItems(from statistics: UsageStatistics) -> [Any] {
        guard let card = ShareCardRenderer.image(for: statistics) else { return items(from: statistics) }
        return [card] + items(from: statistics)
    }

    @MainActor
    @discardableResult
    static func copy(_ statistics: UsageStatistics, to pasteboard: NSPasteboard = .general) -> Bool {
        ShareCardRenderer.copy(statistics, text: linked(statistics), to: pasteboard)
    }

    /// One sentence, no adjectives Vigil has not earned. If nothing was ever
    /// unattended it says so rather than inventing a rescue.
    static func summary(_ statistics: UsageStatistics) -> String {
        let name = Branding.appName
        let held = ElapsedTime.compact(statistics.totalHeld)
        guard statistics.totalRescued > 0 else {
            return String(
                localized: """
                    \(name) has watched \(statistics.totalHolds) agent runs on my Mac and kept it \
                    awake for \(held) of them.
                    """)
        }
        let away = ElapsedTime.compact(statistics.totalAway)
        // A sentence per plural case rather than a glued-in noun: "run"/"runs"
        // does not survive a language that declines it.
        guard statistics.totalRescued > 1 else {
            return String(
                localized: """
                    \(name) kept my Mac awake for \(away) while I was away from it, and saved \
                    1 agent run that would otherwise have died when the Mac went to sleep.
                    """)
        }
        return String(
            localized: """
                \(name) kept my Mac awake for \(away) while I was away from it, and saved \
                \(statistics.totalRescued) agent runs that would otherwise have died when the \
                Mac went to sleep.
                """)
    }

    /// The sentence with the link under it. A card pasted with no way back to the
    /// app is just a picture of some numbers.
    static func linked(_ statistics: UsageStatistics) -> String {
        guard let url = Branding.repositoryURL else { return summary(statistics) }
        return "\(summary(statistics))\n\(url.absoluteString)"
    }
}
