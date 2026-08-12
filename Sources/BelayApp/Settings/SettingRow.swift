import SwiftUI

/// The measurements every pane shares. One label column, one control column,
/// same rhythm everywhere — the thing that makes a preferences window read as
/// one window rather than five.
enum SettingsMetrics {
    static let labelWidth: CGFloat = 200
    static let columnGap: CGFloat = 10
    static let controlWidth: CGFloat = 180
    static let rowSpacing: CGFloat = 10
    static let groupSpacing: CGFloat = 16
    static let paneInsets = EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)
}

/// A row of a settings pane: right-aligned label, control to its right, and an
/// optional caption under the control.
///
/// A `nil` title keeps the label column empty and the control aligned with the
/// rows above it, which is how checkboxes and notes are laid out on macOS.
struct SettingRow<Control: View>: View {
    var title: LocalizedStringKey?
    var explanation: LocalizedStringKey?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.columnGap) {
            label
                .multilineTextAlignment(.trailing)
                .frame(width: SettingsMetrics.labelWidth, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                control()
                if let explanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Built as `Text` rather than a view so the colon cannot wrap onto a line
    /// of its own when the label is long enough to break.
    private var label: Text {
        guard let title else { return Text(verbatim: "") }
        return Text(title) + Text(verbatim: ":")
    }
}

/// A checkbox row. The box sits in the control column with its text beside it,
/// so the label column stays empty.
struct SettingCheckbox: View {
    let title: LocalizedStringKey
    var explanation: LocalizedStringKey?
    /// Only when the visible text is too terse to stand alone out of context.
    var spokenLabel: LocalizedStringResource?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(explanation: explanation) { box }
    }

    @ViewBuilder private var box: some View {
        if let spokenLabel {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
                .accessibilityLabel(Text(spokenLabel))
        } else {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
        }
    }
}

/// A run of checkboxes under one right-aligned category label.
///
/// A pane made only of `SettingCheckbox` leaves the label column empty, and next
/// to Behaviour or Providers it reads as though the controls have slipped to the
/// right — which is exactly what the empty column looks like. System Settings
/// solves it the same way: one category label beside the first checkbox, the
/// rest stacked under it.
///
/// The label sits on the first row's baseline rather than centred on the block,
/// so a group of one and a group of four start at the same height.
struct SettingCheckboxGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.columnGap) {
            (Text(title) + Text(verbatim: ":"))
                .multilineTextAlignment(.trailing)
                .frame(width: SettingsMetrics.labelWidth, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A checkbox without the label column, for use inside `SettingCheckboxGroup`.
struct GroupedCheckbox: View {
    let title: LocalizedStringKey
    var explanation: LocalizedStringKey?
    var spokenLabel: LocalizedStringResource?
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            box
            if let explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var box: some View {
        if let spokenLabel {
            Toggle(title, isOn: $isOn).toggleStyle(.checkbox).accessibilityLabel(Text(spokenLabel))
        } else {
            Toggle(title, isOn: $isOn).toggleStyle(.checkbox)
        }
    }
}

/// Secondary text living in the control column, under the rows it explains.
struct SettingNote: View {
    let text: LocalizedStringKey
    var isProblem = false

    var body: some View {
        SettingRow {
            Text(text)
                .font(.caption)
                .foregroundStyle(isProblem ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Rows that belong together. Groups are separated by a `Divider` in the pane,
/// the way Mail and Pixelmator separate theirs.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            content()
        }
    }
}

/// Pane chrome: the fixed width and the window's insets. Panes lay their own
/// groups out inside it.
struct SettingsStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
            content()
        }
        .padding(SettingsMetrics.paneInsets)
        .frame(width: SettingsPane.width, alignment: .topLeading)
    }
}
