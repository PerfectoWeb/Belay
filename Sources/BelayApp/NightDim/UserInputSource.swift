import CoreGraphics
import Foundation

/// What the person at the machine has done lately, read without an event tap.
///
/// `CGEventSource.secondsSinceLastEventType` needs no Accessibility grant,
/// which a tap would (docs/ROADMAP). Everything here is a poll, so the tick
/// that samples it is the only schedule involved.
enum UserInputSource {
    /// `kCGAnyInputEventType`, which the Swift overlay does not surface. The
    /// fallback can never be taken — a C enum's raw initialiser accepts any
    /// value — but `.null` (0) would merely widen "any input" to "any event".
    private static let anyInput = CGEventType(rawValue: ~0) ?? .null

    /// Seconds since any input at all: keys, buttons, movement, scroll.
    static func secondsSinceAnyInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// Whether a key went down or a button was clicked within `interval`.
    /// Movement is deliberately absent: it restores by distance, not by event.
    static func keyOrClick(within interval: TimeInterval) -> Bool {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        return types.contains {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
                < interval
        }
    }

    /// Where the pointer is, for the travel-since-dim distance.
    static func pointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}
