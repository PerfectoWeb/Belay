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
    /// The refresh mark, drawn where the lower right sparkle sits.
    ///
    /// Two subpaths at their own 104 unit scale, exactly as supplied. Parsed
    /// once and reused: re-parsing per frame would be a hundred times a second
    /// while an agent works, for a shape that never changes.
    private static let arrowArtwork =
        "M94.1897 33.0394L89.8812 2.87707C89.527 0.40422 86.4876 -0.623392 84.7098 1.15436L78.434"
        + "5 7.42973C70.3649 2.56182 61.2035 0 51.7832 0C23.4536 0 0.70906 22.1732 0.000963789 50.4"
        + "789C-0.0376301 52.0262 1.08708 53.3532 2.61641 53.5734L14.792 55.3139C16.6071 55.5788 18"
        + ".2957 54.1537 18.2705 52.2553C18.018 33.5738 33.1066 18.2813 51.7832 18.2813C56.3058 18."
        + "2813 60.7749 19.2007 64.9051 20.9591L58.856 27.0082C57.0894 28.7748 58.0921 31.8235 60.5"
        + "787 32.1796L90.741 36.4881C92.7284 36.7877 94.4747 35.0593 94.1897 33.0394Z M101.383 50."
        + "662L89.2167 48.9243C87.6449 48.7252 85.7383 50.0721 85.7383 52.2033C85.7383 70.6839 70.7"
        + "032 85.7191 52.2226 85.7191C47.7238 85.7191 43.2753 84.8087 39.1604 83.0679L45.0161 77.2"
        + "122C46.7827 75.4456 45.7801 72.3969 43.2934 72.0408L13.1311 67.7292C11.15 67.4463 9.3956"
        + "1 69.1452 9.68242 71.1779L13.9907 101.34C14.3454 103.816 17.3821 104.837 19.1621 103.063"
        + "L25.5892 96.6391C33.62 101.462 42.7754 104 52.2226 104C80.4152 104 103.157 81.9373 103.9"
        + "99 53.7715C104.043 52.2212 102.919 50.8822 101.383 50.662Z"

    private static let arrows: NSBezierPath = {
        let path = NSBezierPath()
        for subpath in SVGPath.subpaths(arrowArtwork, flipHeight: 104) { path.append(subpath) }
        return path
    }()

    /// The update mark: the lower right sparkle swapped for a pair of arrows.
    ///
    /// A dot in the free corner was the first shape and it read as a warning
    /// badge, which is the wrong register for "there is a newer version". This
    /// says what it means instead, and it costs no space because it takes the
    /// place of something already there rather than adding a fourth thing.
    ///
    /// Nothing is punched around it. The corner it occupies is empty artwork
    /// once the sparkle it replaces is not drawn, so a gap would only be a
    /// softened oval bitten out of the star for no reason.
    static func updateMark(alpha: CGFloat) {
        // `artworkSubpaths`, not `parts`: this file is an extension in another
        // file, and `private` does not reach across one.
        let slot = artworkSubpaths[0].bounds
        let box = arrows.bounds
        // The size of the sparkle it replaces, near enough. Bigger was tried
        // twice: 1.42 ran off the edge of the 24 unit box and came out with two
        // sides sliced flat, and 1.16 fitted but sat against the star with no
        // air between them. A ring needs the gap more than it needs the width.
        let side = min(slot.width, slot.height) * 0.98
        let factor = side / max(box.width, box.height)

        // Centred on the sparkle, then pushed back inside if that puts any of
        // it past the edge. The artwork sits hard against the corner, so a mark
        // grown around its centre has nowhere to go but out.
        let margin: CGFloat = 0.35
        var centre = CGPoint(x: slot.midX, y: slot.midY)
        let half = side / 2
        centre.x = min(max(centre.x, half + margin), 24 - half - margin)
        centre.y = min(max(centre.y, half + margin), 24 - half - margin)

        var transform = AffineTransform(translationByX: centre.x, byY: centre.y)
        transform.scale(factor)
        transform.translate(x: -box.midX, y: -box.midY)

        let mark = NSBezierPath()
        mark.append(arrows)
        mark.transform(using: transform)

        fill(mark, alpha: alpha)
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
