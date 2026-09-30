import ApplicationServices
import BelayModules
import Foundation

#if !BELAY_MAS
/// Saying yes to one card: pressed until the card goes.
///
/// An element is a reference to something in another process, safe to send
/// anywhere; the type only predates the word for it.
struct AppPress: @unchecked Sendable {
    /// A card that has only just appeared takes a press and ignores it.
    /// Measured in Claude on 30 September 2026: the first press did nothing
    /// in three seconds, the next one emptied the card in 0.05.
    static let attempts = 10
    static let pause: TimeInterval = 0.4

    let screen: AppScreen
    let card: AppScreen.Card
    let button: AXUIElement
    /// What the card said when the rules agreed to it.
    let texts: [String]

    /// Presses until the card goes. Before every press the card is read
    /// again: the page may put the next request into the same place, and
    /// a yes given to one request must never land on another.
    func perform() -> PressOutcome {
        let began = Date()
        var refused: AXError?
        for attempt in 0..<Self.attempts {
            guard button.isStillThere else {
                return attempt == 0
                    ? .gone : .answered(presses: attempt, seconds: Date().timeIntervalSince(began))
            }
            guard saysTheSame else { return .changed }
            let outcome = screen.dialect.press(button, of: card.process)
            guard outcome == .success else {
                refused = outcome
                Thread.sleep(forTimeInterval: Self.pause)
                continue
            }
            for _ in 0..<4 {
                Thread.sleep(forTimeInterval: Self.pause / 4)
                if !button.isStillThere {
                    return .answered(
                        presses: attempt + 1, seconds: Date().timeIntervalSince(began))
                }
            }
        }
        return .unanswered(presses: Self.attempts, refused: refused?.rawValue ?? 0)
    }

    private var saysTheSame: Bool {
        var now: [String] = []
        var found: AXUIElement?
        screen.collect(card.element, texts: &now, button: &found, depth: 0)
        return now == texts
    }
}
#endif
