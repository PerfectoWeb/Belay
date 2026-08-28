import AppKit

/// The key that shows a menu's longer choices.
///
/// Both Option and Shift, and the order matters for which one gets written
/// down. Option is what macOS itself uses for this: the Apple menu's "Shut
/// Down…" loses its ellipsis under it, Finder's "Copy" counts the items, "Save
/// As…" appears in File. Somebody who wonders whether a menu is hiding
/// anything reaches for Option without being told, which is the whole point of
/// a feature nobody can see.
///
/// Shift is here because it shipped first, in 1.6.2, and is written into that
/// version's notes in seven languages and into the App Store listing. Taking it
/// away to be idiomatic would make yesterday's documentation wrong for the
/// people most likely to have read it. It costs one condition to keep.
enum RevealKey {
    /// Whether either key is down right now.
    static var isHeld: Bool { held(NSEvent.modifierFlags) }

    /// Split out so tests can ask about flags they make up.
    static func held(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) || flags.contains(.shift)
    }
}
