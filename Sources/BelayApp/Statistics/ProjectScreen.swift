import SwiftUI

/// One folder's side of the statistics: what it has cost in sessions, agent
/// time and tokens since Belay started counting, and the recent runs under it.
///
/// The totals come from `ProjectTotals`, not from the rows: the rows are the
/// last fifty sessions overall and this folder's share of them shrinks as
/// other folders get busy. The headline says what is true for all time; the
/// table says what is recent, and its caption admits to being a slice.
struct ProjectScreen: View {
    let folder: String
    let totals: ProjectTotals
    let records: [SessionRecord]
    var onBack: () -> Void = {}

    /// The headline slot, drawn by `StatisticsPane` where the other screens
    /// draw theirs, in exactly their shape — a big line and a caption — so
    /// nothing on the page moves when a folder opens or closes.
    var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: folder)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: totals.caption(withTime: true))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SessionsScreen(records: records, hidesFolder: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("recent sessions in this folder")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
                .padding(.leading, 5)
        }
        // Escape leaves the way a sheet does; the button is for the mouse.
        .onKeyPress(.escape) {
            onBack()
            return .handled
        }
    }
}
