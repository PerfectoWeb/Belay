import Foundation

/// The choices docs/05 puts in the Behaviour pane, as data.
///
/// The picker renders these; the labels live in the String Catalog. Anything not
/// in a list is the "custom" case, which is just the property's own value.
public enum SettingsPresets {
    /// 30 s up to 10 min, then custom. Every one of these has a written label in
    /// the app's `DurationChoice`, and a test fails if one ever does not.
    public static let gracePeriods: [TimeInterval] = [30, 60, 180, 300, 600]

    /// 30 min through 12 h, then nil for "until turned off", where `nil` is "until turned off".
    /// Must contain `AwakePolicy.default.maxContinuousAwake`. It did not, and
    /// the consequence was not cosmetic: the pop-up had no matching tag, drew
    /// blank, and SwiftUI wrote a different value back — silently turning the
    /// maximum-awake backstop off on first launch. `SettingsPresetsTests` now
    /// fails if a default is ever unrepresentable again.
    public static let maxContinuousAwake: [TimeInterval?] = [
        30 * 60, 60 * 60, 2 * 60 * 60, 4 * 60 * 60, 8 * 60 * 60, 10 * 60 * 60, 12 * 60 * 60, nil
    ]

    /// The nearest choice to a stored value.
    ///
    /// The pop-ups have a row per value and no row for anything else, so a value
    /// outside the list draws as an empty box. That is not hypothetical: adding
    /// 5 and 10 minutes to the grace periods and moving the default from 90 s to
    /// a round minute left every existing install holding 90, which is in no
    /// list and showed nothing at all. Snapping makes the class of bug
    /// impossible rather than relying on a migration being remembered.
    public static func nearest(_ value: TimeInterval, in choices: [TimeInterval]) -> TimeInterval {
        choices.min { abs($0 - value) < abs($1 - value) } ?? value
    }
}
