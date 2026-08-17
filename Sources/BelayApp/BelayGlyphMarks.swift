import AppKit

/// The two things drawn on top of the mark rather than as part of it.
///
/// Both work the same way and that is why they live together: neither paints a
/// second colour, because this is a template image and macOS tints every filled
/// pixel identically. They punch a hole with `destinationOut` and then fill
/// inside it, which is the only way to get separation out of a one-colour
/// drawing.
///
/// Split from `BelayGlyph.swift` to keep that file under the length rule, not
/// because the drawing is a separate idea.
extension BelayGlyph {
    /// The update mark: a dot in the corner the artwork leaves empty.
    ///
    /// Bottom left, because the two small sparkles occupy both right-hand
    /// corners and the big one owns the middle. Measured, not guessed: the three
    /// subpaths span x 15 to 24 and y 0 to 9, x 0 to 20 and y 3 to 23, and x 17
    /// to 24 and y 17 to 24, which leaves the lower left free.
    ///
    /// The gap around it is what makes it read as a badge rather than as a
    /// fourth sparkle. It has to be punched rather than painted: this is a
    /// template image, so macOS tints every filled pixel the same colour and a
    /// "background" behind the dot would be the same ink as the dot.
    static func updateDot() {
        let centre = CGPoint(x: 3.1, y: 3.1)
        let dot: CGFloat = 2.2
        let gap: CGFloat = 3.5

        NSGraphicsContext.saveGraphicsState()
        // Opaque first. `destinationOut` takes the alpha of the fill, so a
        // colour left over from an earlier draw cuts only as deep as its own
        // alpha and the gap comes out grey instead of clear.
        NSColor(calibratedWhite: 0, alpha: 1).setFill()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        circle(at: centre, radius: gap).fill()
        NSGraphicsContext.restoreGraphicsState()

        fill(circle(at: centre, radius: dot), alpha: 1)
    }

    static func circle(at centre: CGPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(
            ovalIn: CGRect(
                x: centre.x - radius, y: centre.y - radius,
                width: radius * 2, height: radius * 2))
    }

    /// The safety stop: two bars cut straight out of the big star.
    ///
    /// Not a strike and not a badge: a strike says *forbidden*, and at 17 points
    /// a bordered circle reads as a notification dot. Both are promises Belay is
    /// not making while it is running and has let go on purpose to save the
    /// battery.
    ///
    /// So nothing is drawn now, only removed, and the tinting macOS applies to
    /// a template image cannot be fought. The numbers are the star's, not the
    /// 24-point box's: part 1 spans x 0 to 19.98 and y 3 to 23, middle (10, 13).
    static func pausedBars() {
        let centre = CGPoint(x: 9.99, y: 13)
        // Sized for 17 points, the only size the menu bar draws this at, where
        // a bar this wide lands on 1.6 of them. Thinner than this it disappears.
        let width: CGFloat = 2.3
        let gap: CGFloat = 2.0
        let height: CGFloat = 6.4

        // Opaque, or the cut is only as deep as the last fill's alpha and the
        // bars come out as grey stripes instead of gaps.
        NSColor(calibratedWhite: 0, alpha: 1).setFill()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        for side in [-1.0, 1.0] {
            let bar = NSRect(
                x: centre.x + CGFloat(side) * gap / 2 - (side < 0 ? width : 0),
                y: centre.y - height / 2,
                width: width, height: height)
            // Rounded ends: the star has no straight edges of its own, and a
            // square-cut bar inside it reads as damage.
            NSBezierPath(roundedRect: bar, xRadius: width / 2, yRadius: width / 2).fill()
        }
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
