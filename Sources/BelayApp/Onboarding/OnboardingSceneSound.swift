import Foundation

/// The one part of the welcome scene that is heard rather than seen.
///
/// Its own file because `OnboardingScene` had reached the length this project
/// allows, and because the split is a real one: everything left in there is a
/// function of the time and nothing else, and this is the only thing in the
/// scene that reaches out of the drawing and does something.
///
/// Static, and handed the moment the loop started rather than reading it off
/// the view. That is what lets it live out here at all, and it makes the one
/// thing that matters about this code explicit at the call site: the sound and
/// the picture are told the same time.
extension OnboardingScene {
    /// What is heard, and when. Four agents finishing, the Mac letting go, and
    /// the Mac coming back.
    ///
    /// Gated the same way every other sound in the app is — the system's
    /// interface-sounds preference first, then Belay's own switch — because a
    /// welcome screen is the worst possible place to be the exception.
    ///
    /// Internal so a test can walk it: whether two of these can be heard at
    /// once is a property of this list and the length of the files, and both
    /// are known without playing anything.
    static var cues: [(at: Double, sound: Feedback.Sound)] {
        (0..<4).map { (at: popTime($0), sound: Feedback.Sound.agentPop) }
            + [(at: 8.35, sound: .driftingOff), (at: 10.8, sound: .wakingUp)]
    }

    /// How late a cue may be and still be worth playing. Past this the moment
    /// it belongs to is off the screen, and a pop with nothing popping is worse
    /// than silence.
    private static let slack: Double = 0.35

    /// Walks the cues, waiting until each is due by the same clock the picture
    /// is drawn from, and goes round with it.
    ///
    /// Due by, not a gap after the last one. Sleeping the gaps was the first
    /// version and it drifts, badly: `Task.sleep` guarantees a floor and not a
    /// deadline, this runs on the main actor, and the main actor is redrawing
    /// the scene thirty times a second, so every one of the seven waits in a
    /// pass wakes up a little late and the error accumulates. Measured at about
    /// three quarters of a second lost per pass — by the fifth the sigh lands
    /// on a lit screen. Anchoring every wait to `began` cannot accumulate:
    /// a late wake-up shortens the next wait instead of pushing it back.
    ///
    /// Cancelled with the view, so a window closed mid-pass makes no noise
    /// afterwards.
    static func soundtrack(from began: Date) async {
        var pass = 0.0
        while !Task.isCancelled {
            for cue in Self.cues {
                let due = pass * Self.loop + cue.at
                let wait = due - Date().timeIntervalSince(began)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                if Task.isCancelled { return }
                if Date().timeIntervalSince(began) - due < Self.slack {
                    Feedback.play(cue.sound)
                }
            }
            pass += 1
        }
    }
}
