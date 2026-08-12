import Foundation

/// The choices docs/05 puts in the Behaviour pane, as data.
///
/// The picker renders these; the labels live in the String Catalog. Anything not
/// in a list is the "custom" case, which is just the property's own value.
public enum SettingsPresets {
    /// 30 s up to 10 min, then custom. Every one of these has a written label in
    /// the app's `DurationChoice`, and a test fails if one ever does not.
    public static let gracePeriods: [TimeInterval] = [30, 60, 180, 300, 600]

    /// 30 min / 1 h / 2 h / until turned off, where `nil` is "until turned off".
    /// Must contain `AwakePolicy.default.maxContinuousAwake`. It did not, and
    /// the consequence was not cosmetic: the pop-up had no matching tag, drew
    /// blank, and SwiftUI wrote a different value back — silently turning the
    /// maximum-awake backstop off on first launch. `SettingsPresetsTests` now
    /// fails if a default is ever unrepresentable again.
    public static let maxContinuousAwake: [TimeInterval?] = [
        30 * 60, 60 * 60, 2 * 60 * 60, 4 * 60 * 60, 8 * 60 * 60, nil
    ]
}
