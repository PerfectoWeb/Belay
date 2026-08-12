import Foundation

/// What a duration is called in a settings pop-up.
///
/// Not `ElapsedTime.compact`. That one is built for the panel's ticking column,
/// where "1h 04m" has to hold a fixed width so the row beside it does not shift
/// once a minute. A pop-up has no such constraint and every other requirement:
/// a space before the unit, no padding zero on a round hour, and a plural form
/// that is right in six languages.
///
/// Written out per value rather than computed. Russian needs "1 час", "2 часа"
/// and "8 часов"; German and Italian want their own separators. Eleven strings
/// a translator can simply read is worth more than one clever function with
/// plural rules nobody can check, and the list is short because the choices are.
enum DurationChoice {
    /// A `String`, not a `LocalizedStringResource`: the fallback is already
    /// formatted, and wrapping it would ask the catalogue for the key "%@".
    static func label(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return String(localized: "Until turned off") }
        guard let written = written[Int(seconds.rounded())] else {
            // Only reachable from a value stored by a build whose list differed.
            // `DurationChoiceTests` fails if a shipped preset lands here.
            return ElapsedTime.compact(seconds)
        }
        return String(localized: written)
    }

    /// Every choice the two pop-ups offer, keyed by its value in seconds.
    private static let written: [Int: String.LocalizationValue] = [
        30: "30 sec",
        60: "1 min",
        180: "3 min",
        300: "5 min",
        600: "10 min",
        1800: "30 min",
        3600: "1 hour",
        7200: "2 hours",
        14400: "4 hours",
        28800: "8 hours"
    ]

    /// True when the value has a written label rather than the fallback.
    static func isWritten(_ seconds: TimeInterval?) -> Bool {
        guard let seconds else { return true }
        return written[Int(seconds.rounded())] != nil
    }
}
