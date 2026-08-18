import SwiftUI

/// The word on the button that closes What's New.
///
/// Picked at random rather than fixed, because this window is seen once per
/// release and a small change is a small pleasure. Chosen once per launch and
/// held, so the button does not rename itself while somebody is reading.
///
/// Every line is short, positive, and says the same thing: we are done here.
/// Nothing here is an instruction, so none of them can be misread as one.
@MainActor
enum WhatsNewFarewell {
    /// `LocalizedStringKey` is not `Sendable`, and should not be: SwiftUI
    /// resolves it against the environment as it draws, which is what lets the
    /// language picker change a window that is already open. So this lives on
    /// the main actor, where the view is.
    static let lines: [LocalizedStringKey] = [
        "Let's go",
        "Sounds good",
        "Got it",
        "Looks good",
        "Nice one",
        "Good to go",
        "Lovely"
    ]

    static let line: LocalizedStringKey = lines.randomElement() ?? "Got it"
}
