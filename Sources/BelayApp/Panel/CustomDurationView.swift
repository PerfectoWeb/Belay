import SwiftUI

// Animates nothing that can change the panel's height. This view lives in a
// sheet over the panel; the pill slides and colours fade inside a fixed frame.

/// The accessory inside the custom-length alert: a two-tab switch drawn like
/// the panel's mode picker, the fields for the chosen tab, and a footnote
/// that always shows the other reading of the same answer.
struct CustomDurationView: View {
    @ObservedObject var model: CustomDurationModel
    @FocusState private var focused: Field?

    private enum Field { case hours, minutes }

    var body: some View {
        VStack(spacing: 10) {
            ModeSwitch(mode: $model.mode)
                .frame(width: 190)
            Group {
                switch model.mode {
                case .duration: durationFields
                case .until: ClockField(minutes: $model.untilMinutes)
                }
            }
            .frame(height: 24)
            // A fixed slot even while invalid, so the alert never changes
            // height under the cursor.
            Text(footnote ?? " ")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .onAppear { focused = .hours }
    }

    private var durationFields: some View {
        HStack(spacing: 4) {
            digitField($model.hours, field: .hours)
            Text(verbatim: ":").foregroundStyle(.secondary)
            digitField($model.minutes, field: .minutes)
        }
    }

    /// Digits only, two at most; two digits in the hours hand focus to the
    /// minutes — the way a date field behaves anywhere on a Mac.
    private func digitField(_ text: Binding<String>, field: Field) -> some View {
        TextField(text: text) { EmptyView() }
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 13).monospacedDigit())
            .focused($focused, equals: field)
            .frame(width: 44, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .onChange(of: text.wrappedValue) { _, value in
                let digits = String(value.filter(\.isNumber).prefix(2))
                if digits != value { text.wrappedValue = digits }
                if field == .hours, digits.count == 2 { focused = .minutes }
            }
    }

    /// The other reading of the current answer: a duration names its end
    /// time, an end time names its duration.
    private var footnote: String? {
        guard let seconds = model.result() else { return nil }
        switch model.mode {
        case .duration:
            let ends = Date(timeIntervalSinceNow: seconds)
                .formatted(date: .omitted, time: .shortened)
            return String(localized: "Ends at \(ends)")
        case .until:
            return String(localized: "\(ElapsedTime.compact(seconds)) from now")
        }
    }
}

/// For / Until, drawn the way the panel draws Auto / Always on / Off: one
/// track, two tabs, and a pill that slides between them on the same spring —
/// so the dialog reads as the panel's own, not as a stock form control.
private struct ModeSwitch: View {
    @Binding var mode: CustomDurationModel.Mode
    @State private var hovered: CustomDurationModel.Mode?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            tab(.duration, symbol: "timer", title: "For")
            tab(.until, symbol: "clock", title: "Until")
        }
        .padding(2)
        .background(alignment: .leading) {
            GeometryReader { geometry in
                let tab = (geometry.size.width - 4 - 2) / 2
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlAccentColor))
                    .frame(width: tab, height: geometry.size.height - 4)
                    .offset(x: 2 + (mode == .until ? tab + 2 : 0), y: 2)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78),
                        value: mode)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .contain)
    }

    private func tab(
        _ target: CustomDurationModel.Mode, symbol: String, title: LocalizedStringKey
    ) -> some View {
        let isSelected = mode == target
        return Button {
            mode = target
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.white : .primary.opacity(hovered == target ? 1 : 0.6))
            .animation(.easeInOut(duration: 0.18), value: hovered)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? target : (hovered == target ? nil : hovered) }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
