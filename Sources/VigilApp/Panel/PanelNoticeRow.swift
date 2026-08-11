import SwiftUI

/// A single inline line for something that went wrong or needs one tap to fix.
///
/// Deliberately not an alert or a sheet: a menu bar utility that throws modals
/// at you is one you turn off (docs/05).
struct PanelNoticeRow: View {
    let symbolName: String
    /// Comes from the detection layer at runtime, so it is displayed verbatim
    /// rather than treated as a localisation key.
    let message: String
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityLabel(actionTitle)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .accessibilityElement(children: .contain)
    }
}
