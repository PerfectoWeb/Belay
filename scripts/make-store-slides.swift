// Renders the App Store slides.
//
//   swift scripts/make-store-slides.swift <captures-dir> <output-dir>
//
// The canvas is 2880x1800, which is the largest size App Store Connect accepts
// for macOS and covers the other three because all four are 16:10. Output is
// opaque: an alpha channel is rejected at upload.
//
// Type is Charter Bold for display and Avenir Next for everything functional.
// Both cover Cyrillic, which is why they are here and Bebas Neue, Optima and
// Charter Black are not: none of those three has any Cyrillic at all, so the
// set would break the first time it is localised.
//
// Every number below is a pixel on the 2880x1800 canvas. Text is placed by
// baseline rather than by frame, so the grid holds regardless of what the font
// thinks its line box is.
import AppKit
import CoreText

// MARK: - The grid

enum Grid {
    static let width: CGFloat = 2880
    static let height: CGFloat = 1800
    static let margin: CGFloat = 168
    static let columnWidth: CGFloat = 168
    static let gutter: CGFloat = 48

    static func column(_ index: Int) -> CGFloat { margin + CGFloat(index - 1) * (columnWidth + gutter) }
    /// Width of a span from column `from` through column `to`, inclusive.
    static func span(_ from: Int, _ to: Int) -> CGFloat {
        CGFloat(to - from + 1) * columnWidth + CGFloat(to - from) * gutter
    }
    /// The text column every slide but the last one uses.
    static let textColumn = span(1, 5)
}

enum Ink {
    static let field = NSColor(srgbRed: 0x1B / 255, green: 0x23 / 255, blue: 0x40 / 255, alpha: 1)
    static let lift = NSColor(srgbRed: 0x46 / 255, green: 0x54 / 255, blue: 0x8A / 255, alpha: 1)
    static let vignette = NSColor(srgbRed: 0x0A / 255, green: 0x0E / 255, blue: 0x1C / 255, alpha: 1)
    static let primary = NSColor(srgbRed: 0xF4 / 255, green: 0xF7 / 255, blue: 1, alpha: 1)
    static let secondary = NSColor(srgbRed: 0xB9 / 255, green: 0xC4 / 255, blue: 0xDE / 255, alpha: 1)
    static let tertiary = NSColor(srgbRed: 0x8B / 255, green: 0x97 / 255, blue: 0xB8 / 255, alpha: 1)
    static let sparkle = NSColor(srgbRed: 0xC4 / 255, green: 0xE1 / 255, blue: 1, alpha: 1)
    static let accent = NSColor(srgbRed: 0x23 / 255, green: 0x79 / 255, blue: 1, alpha: 1)
    static let plateTop = NSColor(srgbRed: 0x26 / 255, green: 0x2E / 255, blue: 0x4C / 255, alpha: 1)
    static let plateBottom = NSColor(srgbRed: 0x0D / 255, green: 0x0F / 255, blue: 0x1F / 255, alpha: 1)
    static let shadow = NSColor(srgbRed: 0x05 / 255, green: 0x07 / 255, blue: 0x0F / 255, alpha: 1)
}

/// One role in the type scale.
struct Style {
    var font: String
    var size: CGFloat
    var leading: CGFloat
    var kern: CGFloat
    var colour: NSColor
    var uppercase = false

    static let eyebrow = Style(
        font: "AvenirNext-DemiBold", size: 34, leading: 48, kern: 5.4, colour: Ink.sparkle,
        uppercase: true)
    static let hero = Style(
        font: "Charter-Bold", size: 132, leading: 144, kern: -2.6, colour: Ink.primary)
    static let headline = Style(
        font: "Charter-Bold", size: 96, leading: 120, kern: -1.9, colour: Ink.primary)
    static let subhead = Style(
        font: "AvenirNext-Medium", size: 48, leading: 72, kern: 0, colour: Ink.secondary)
    static let caption = Style(
        font: "AvenirNext-Medium", size: 30, leading: 36, kern: 0.6, colour: Ink.tertiary)
    // 88, not the 120 the spec asked for: "3h 42m" is the widest figure and at
    // 120 it ran straight through the number beside it.
    static let figure = Style(
        font: "Charter-Bold", size: 88, leading: 108, kern: -1.8, colour: Ink.primary)
    static let figureLabel = Style(
        font: "AvenirNext-DemiBold", size: 26, leading: 36, kern: 3.1, colour: Ink.tertiary,
        uppercase: true)
    static let language = Style(
        font: "Charter-Bold", size: 52, leading: 72, kern: -1, colour: Ink.primary)
    static let gloss = Style(
        font: "AvenirNext-Medium", size: 30, leading: 72, kern: 0.4, colour: Ink.tertiary)
}

// MARK: - Drawing

/// Lays out one run of text and draws it by baseline.
///
/// `CTTypesetter` rather than `NSAttributedString.draw(in:)`: the latter places
/// a frame and lets the font decide where the first baseline lands, which puts
/// every slide's grid at the mercy of Charter's ascent.
@discardableResult
func text(
    _ string: String, _ style: Style, x: CGFloat, baseline: CGFloat, width: CGFloat = 4000,
    align: NSTextAlignment = .left
) -> CGFloat {
    let content = style.uppercase ? string.uppercased() : string
    guard let font = NSFont(name: style.font, size: style.size) else {
        FileHandle.standardError.write("missing font \(style.font)\n".data(using: .utf8)!)
        exit(1)
    }
    let attributed = NSAttributedString(
        string: content, attributes: [.font: font, .kern: style.kern, .foregroundColor: style.colour])
    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
    var start = 0
    var y = baseline
    let context = NSGraphicsContext.current!.cgContext
    while start < attributed.length {
        let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let offset: CGFloat =
            switch align {
            case .center: (width - bounds.width) / 2
            case .right: width - bounds.width
            default: 0
            }
        context.textPosition = CGPoint(x: x + offset, y: Grid.height - y)
        CTLineDraw(line, context)
        start += count
        y += style.leading
    }
    return y - style.leading
}

/// The background every slide shares: a flat field, a halo where the window is,
/// and a vignette. The halo is what makes a dark app window read as a separate
/// object rather than dissolving into a dark slide.
func background(liftCentre: CGPoint, liftRadius: CGFloat = 1500) {
    let context = NSGraphicsContext.current!.cgContext
    Ink.field.setFill()
    NSRect(x: 0, y: 0, width: Grid.width, height: Grid.height).fill()

    func radial(_ colour: NSColor, _ stops: [(CGFloat, CGFloat)], centre: CGPoint, from: CGFloat, to: CGFloat) {
        let colours = stops.map { colour.withAlphaComponent($0.1).cgColor } as CFArray
        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours,
                locations: stops.map { $0.0 })
        else { return }
        let flipped = CGPoint(x: centre.x, y: Grid.height - centre.y)
        context.drawRadialGradient(
            gradient, startCenter: flipped, startRadius: from, endCenter: flipped, endRadius: to,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    radial(Ink.lift, [(0, 0.85), (0.45, 0.42), (1, 0)], centre: liftCentre, from: 0, to: liftRadius)
    radial(
        Ink.vignette, [(0, 0), (0.5, 0.18), (1, 0.55)], centre: CGPoint(x: 1440, y: 900), from: 900,
        to: 1900)
}

/// A captured window, shadowed and hairlined, fitted into `box` without ever
/// being upscaled past the point where its own 11 pt text stops being legible.
func window(_ image: NSImage?, in box: NSRect, shadowStrength: CGFloat = 1, framed: Bool = true) {
    let context = NSGraphicsContext.current!.cgContext
    let radius: CGFloat = 20
    guard let image else {
        // A placeholder, so the layout can be judged before the captures exist.
        context.saveGState()
        NSColor(srgbRed: 0.08, green: 0.09, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
        Ink.sparkle.withAlphaComponent(0.26).setStroke()
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        path.lineWidth = 2
        path.stroke()
        context.restoreGState()
        return
    }
    let fitted = fit(image.size, into: box)
    for (blur, offset, alpha) in [(120.0, 48.0, 0.50), (32.0, 12.0, 0.38)] {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -offset), blur: blur,
            color: Ink.shadow.withAlphaComponent(alpha * shadowStrength).cgColor)
        image.draw(in: fitted)
        context.restoreGState()
    }
    image.draw(in: fitted)
    // The hero's capture is a slice of screen, menu bar and all, so it has no
    // window edge to trace. Stroking a rounded rectangle around it would draw a
    // window that is not there.
    guard framed else { return }
    Ink.sparkle.withAlphaComponent(0.26).setStroke()
    let outline = NSBezierPath(
        roundedRect: fitted.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
    outline.lineWidth = 2
    outline.stroke()
}

func fit(_ size: NSSize, into box: NSRect) -> NSRect {
    let scale = min(box.width / size.width, box.height / size.height)
    let width = size.width * scale, height = size.height * scale
    return NSRect(
        x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
}

/// A rule under a headline. Four pixels of accent, the one saturated thing on
/// the slide.
func accentRule(x: CGFloat, y: CGFloat, width: CGFloat = 168) {
    Ink.accent.setFill()
    NSRect(x: x, y: Grid.height - y, width: width, height: 4).fill()
}

// MARK: - The mark

/// The lockup, drawn from `Resources/Brand`. Those files are the wordmark; a
/// second copy of it, redrawn here from the path data, would be a second thing
/// to keep in step and the first one to drift.
func wordmark(centreX: CGFloat? = nil, left: CGFloat = 0, baseline: CGFloat, size: CGFloat) {
    guard let image = NSImage(contentsOfFile: "Resources/Brand/belay-wordmark-dark@3x.png") else {
        return
    }
    // The mark is 26/36 of the word's point size and sits on the baseline, so
    // the artwork's own height maps to the lockup height at this size.
    let height = size * 48.52 / 36
    let width = height * image.size.width / image.size.height
    let x = centreX.map { $0 - width / 2 } ?? left
    image.draw(
        in: NSRect(x: x, y: Grid.height - baseline - height * 0.72, width: width, height: height))
}

/// The app icon, at whatever size the slide wants it.
func appIcon(centreX: CGFloat, top: CGFloat, size: CGFloat) {
    guard
        let image = NSImage(
            contentsOfFile: "Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
    else { return }
    image.draw(
        in: NSRect(x: centreX - size / 2, y: Grid.height - top - size, width: size, height: size))
}

// MARK: - Slides

func render(_ name: String, _ body: () -> Void, to directory: String) {
    // Drawn with an alpha channel because a bitmap context cannot be created
    // without one, then written without it because App Store Connect rejects a
    // screenshot that has one. The background covers the whole canvas, so
    // dropping the channel loses nothing.
    let width = Int(Grid.width), height = Int(Grid.height)
    let canvas = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
    NSGraphicsContext.current?.imageInterpolation = .high
    body()
    NSGraphicsContext.restoreGraphicsState()

    let opaque = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: width * 3, bitsPerPixel: 24)!
    let source = canvas.bitmapData!, destination = opaque.bitmapData!
    for pixel in 0..<(width * height) {
        for channel in 0..<3 {
            destination[pixel * 3 + channel] = source[pixel * 4 + channel]
        }
    }
    let tagged = opaque.retagging(with: NSColorSpace.sRGB) ?? opaque
    let path = "\(directory)/\(name).png"
    try! tagged.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print(path)
}

let captures = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let output = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "."

func capture(_ name: String) -> NSImage? {
    NSImage(contentsOfFile: "\(captures)/\(name).png")
}

// 1 — Hero.
render(
    "01-hero",
    {
        background(liftCentre: CGPoint(x: 2184, y: 900))
        wordmark(left: Grid.margin, baseline: 222, size: 60)
        text("For local AI coding agents", .eyebrow, x: Grid.margin, baseline: 480)
        text(
            "Stays awake while the agent is working.", .hero, x: Grid.margin, baseline: 648,
            width: Grid.textColumn)
        text(
            """
            Belay watches Claude Code, Codex, Gemini CLI and Cline, then lets the Mac sleep the \
            way it always did.
            """, .subhead, x: Grid.margin, baseline: 1080, width: Grid.textColumn)
        text(
            "No account. No tracking. Nothing leaves your Mac.", .caption, x: Grid.margin,
            baseline: 1584)
        window(
            capture("panel"), in: NSRect(x: 1584, y: 456, width: 1128, height: 888),
            framed: false)
    }, to: output)

// 2 — Providers.
render(
    "02-providers",
    {
        background(liftCentre: CGPoint(x: 2047, y: 900))
        text("Providers", .eyebrow, x: Grid.margin, baseline: 636)
        text(
            "Five ways to know an agent is running.", .headline, x: Grid.margin, baseline: 780,
            width: Grid.textColumn)
        accentRule(x: Grid.margin, y: 948)
        text(
            """
            Switch on the tools you actually use. The folder watcher covers anything else that \
            writes files while it works.
            """, .subhead, x: Grid.margin, baseline: 1068, width: Grid.textColumn)
        window(capture("providers"), in: NSRect(x: 1382, y: 280, width: 1330, height: 1240))
    }, to: output)

// 3 — Statistics.
render(
    "03-statistics",
    {
        background(liftCentre: CGPoint(x: 2047, y: 900))
        text("Statistics", .eyebrow, x: Grid.margin, baseline: 564)
        text(
            "It counts the time you were away.", .headline, x: Grid.margin, baseline: 708,
            width: Grid.textColumn)
        accentRule(x: Grid.margin, y: 876)
        text(
            """
            Time held while you are at the keyboard is time the Mac was never going to sleep. \
            That is not counted here.
            """, .subhead, x: Grid.margin, baseline: 948, width: Grid.textColumn)
        // The three numbers are the ones in the capture beside them. A figure
        // on a slide that the screenshot does not show is inaccurate metadata.
        for (index, figure) in [("19", "runs saved"), ("3h 42m", "longest run"), ("129", "runs watched")]
            .enumerated()
        {
            let x = Grid.margin + CGFloat(index) * 372
            text(figure.0, .figure, x: x, baseline: 1284)
            text(figure.1, .figureLabel, x: x, baseline: 1332)
        }
        window(capture("statistics"), in: NSRect(x: 1382, y: 280, width: 1330, height: 1240))
    }, to: output)

// 4 — Behaviour.
render(
    "04-behaviour",
    {
        background(liftCentre: CGPoint(x: 2112, y: 860))
        text("Behaviour", .eyebrow, x: Grid.margin, baseline: 636)
        text(
            "You decide when it lets go.", .headline, x: Grid.margin, baseline: 780,
            width: Grid.textColumn)
        accentRule(x: Grid.margin, y: 948)
        text(
            """
            Wait a few minutes after the agent goes quiet, cap the time awake, and stop on low \
            battery. Belay tells you when an agent needs a reply.
            """, .subhead, x: Grid.margin, baseline: 1068, width: Grid.textColumn)
        window(
            capture("notifications"), in: NSRect(x: 1416, y: 384, width: 1200, height: 1060),
            shadowStrength: 0.7)
        window(capture("behaviour"), in: NSRect(x: 1512, y: 564, width: 1200, height: 1060))
    }, to: output)

// 5 — Languages.
render(
    "05-languages",
    {
        background(liftCentre: CGPoint(x: 2112, y: 900))
        text("Six languages", .eyebrow, x: Grid.margin, baseline: 480)
        text(
            "Every word is translated.", .headline, x: Grid.margin, baseline: 624,
            width: Grid.textColumn)
        accentRule(x: Grid.margin, y: 792)
        text(
            """
            The menus, the notifications, the statistics and the About page. Pick a language in \
            Settings.
            """, .subhead, x: Grid.margin, baseline: 864, width: Grid.textColumn)
        let rows = [
            ("English", "English"), ("Русский", "Russian"), ("Deutsch", "German"),
            ("Español", "Spanish"), ("Français", "French"), ("Italiano", "Italian")
        ]
        for (index, row) in rows.enumerated() {
            let baseline = 1080 + CGFloat(index) * 72
            text(row.0, .language, x: Grid.margin, baseline: baseline)
            text(row.1, .gloss, x: Grid.margin, baseline: baseline, width: 1032, align: .right)
            Ink.sparkle.withAlphaComponent(0.14).setFill()
            NSRect(x: Grid.margin, y: Grid.height - baseline - 22, width: 1032, height: 2).fill()
        }
        window(capture("general"), in: NSRect(x: 1512, y: 340, width: 1200, height: 1120))
    }, to: output)

// 6 — Leave a review.
render(
    "06-review",
    {
        background(liftCentre: CGPoint(x: 1440, y: 560), liftRadius: 1100)
        var generator = SplitMix(seed: 0x5EED_1234)
        for _ in 0..<90 {
            let x = generator.unit() * Grid.width
            let y = generator.unit() * Grid.height
            guard !(x > 660 && x < 2220 && y > 840 && y < 1260) else { continue }
            let radius = 1.5 + generator.unit() * 2.5
            NSColor.white.withAlphaComponent(0.10 + generator.unit() * 0.35).setFill()
            NSBezierPath(
                ovalIn: NSRect(
                    x: x, y: Grid.height - y, width: radius * 2, height: radius * 2)
            ).fill()
        }
        appIcon(centreX: 1440, top: 372, size: 384)

        text(
            "If Belay saved you a run, say so.", .headline, x: 1440 - 840, baseline: 912,
            width: 1680, align: .center)
        text(
            "A rating on the Mac App Store is how the next person finds it. Two lines is plenty.",
            .subhead, x: 1440 - 732, baseline: 1152, width: 1464, align: .center)
        for index in 0..<5 {
            let x = 1212 + CGFloat(index) * 96
            let outline = NSBezierPath()
            let centre = CGPoint(x: x + 36, y: Grid.height - 1380)
            for point in 0..<8 {
                let angle = Double(point) * .pi / 4 - .pi / 2
                let radius: CGFloat = point % 2 == 0 ? 36 : 13
                let next = CGPoint(
                    x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
                point == 0 ? outline.move(to: next) : outline.line(to: next)
            }
            outline.close()
            outline.lineWidth = 4
            Ink.sparkle.withAlphaComponent(0.40).setStroke()
            outline.stroke()
        }
        wordmark(centreX: 1440, baseline: 1620, size: 48)
    }, to: output)

// MARK: - Support

/// Deterministic noise, so the starfield is the same on every run.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return Double(mixed >> 11) / Double(1 << 53)
    }
}
