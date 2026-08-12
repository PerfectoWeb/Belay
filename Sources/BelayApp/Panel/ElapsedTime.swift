import Foundation

/// Duration wording for the session rows and the footer.
///
/// Hand-rolled rather than `DateComponentsFormatter` because the panel needs a
/// fixed two-character minute field ("1h 04m") so a ticking row does not shift
/// its neighbours sideways once a minute, and because a pure function is the
/// only version of this that can be tested without a locale fixture.
enum ElapsedTime {
    /// Compact form: "45s", "12m", "1h 04m", "3d 04h".
    static func compact(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval.rounded(.down)))
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = (total / 3600) % 24
        let days = total / 86400

        // Localised: the unit letters are English abbreviations, and this string
        // is the Statistics headline and the share card's largest number.
        if days > 0 { return String(localized: "\(days)d \(padded(hours))h") }
        if hours > 0 { return String(localized: "\(hours)h \(padded(minutes))m") }
        if minutes > 0 { return String(localized: "\(minutes)m") }
        return String(localized: "\(seconds)s")
    }

    /// Spoken form for `accessibilityLabel`, where "1h 04m" is read as noise.
    static func spoken(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval.rounded(.down)))
        let minutes = (total / 60) % 60
        let hours = total / 3600

        // Whole phrases: VoiceOver reads these, and every one of them ends up
        // inside another localised sentence.
        if hours > 0 && minutes > 0 {
            return String(localized: "\(hours) hours \(minutes) minutes")
        }
        if hours > 0 { return String(localized: "\(hours) hours") }
        if minutes > 0 { return String(localized: "\(minutes) minutes") }
        return String(localized: "\(total) seconds")
    }

    private static func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
