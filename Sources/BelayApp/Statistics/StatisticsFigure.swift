import SwiftUI

/// One number with its caption, the unit every figure row in the statistics
/// pane is built from.
///
/// A counting number has to redraw, not dissolve — until the reveal is over.
/// After it, the only changes are a hover borrowing the row and handing it
/// back, and those roll digit by digit (`numericText`), which is the system's
/// own way of saying "same counter, different value".
struct StatisticsFigure: View {
    let value: String
    let caption: LocalizedStringKey
    var morphs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .transaction { $0.animation = morphs ? .easeOut(duration: 0.25) : nil }
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
