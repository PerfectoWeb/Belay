// Renders the repository's social artwork: the README masthead and the Open
// Graph card.
//
//   swift scripts/make-social.swift [output-dir]        # default Promo/Social
//
// Same house as `img/panel.png` on the site, and deliberately so: a purple to
// blue field with a drawing office behind it, the lockup in white, one line of
// type. That image was made by hand in a design tool, so the two could drift;
// this file is the half that can at least be re-rendered from a number.
//
// Two sizes, and both are fixed by somebody else's rules rather than by taste:
//
//   og.png       1280x640, the card GitHub, Slack, Discord and iMessage unfurl.
//                Anything with a different aspect gets cropped by somebody.
//   masthead.png 1280x400, the first thing in README.md. Wider than it is tall
//                because it has to survive being scaled into a phone's width.
//
// The linework is generated, not drawn. It is the same trick the starfield in
// the About panel uses: a seeded generator, so the marks land in the same place
// on every run and a re-render is a no-op in git rather than a diff of noise.
import AppKit
import CoreText

let output = CommandLine.arguments.dropFirst().first ?? "Promo/Social"

// MARK: - The field

enum Ink {
    /// The two ends of the gradient, sampled off the site's own panel artwork
    /// rather than guessed: 131,65,232 at the top and 33,77,240 at the bottom.
    static let violet = NSColor(srgbRed: 0x83 / 255, green: 0x41 / 255, blue: 0xE8 / 255, alpha: 1)
    static let blue = NSColor(srgbRed: 0x21 / 255, green: 0x4D / 255, blue: 0xF0 / 255, alpha: 1)
    static let line = NSColor.white
}

/// Deterministic noise. `SystemRandomNumberGenerator` would move every mark on
/// every render, which turns a rebuild into a diff nobody can review.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat { low + unit() * (high - low) }
}

func gradient(in rect: NSRect) {
    // Violet at the top left falling to blue at the bottom right, which is the
    // way the reference runs. Mostly down, with enough lean to read as light
    // coming from somewhere rather than as a backdrop.
    let ramp = NSGradient(starting: Ink.violet, ending: Ink.blue)
    ramp?.draw(in: rect, angle: -72)
}

/// The drawing office: rectangles, arcs, dashed runs and coordinate labels, all
/// at an opacity where they are texture rather than content. Nothing here means
/// anything, and it is not supposed to — it is the visual language of a plan
/// view, borrowed to say "this is an instrument, not a poster".
func blueprint(in rect: NSRect, seed: UInt64) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    var noise = SplitMix(seed: seed)
    let unitSize = min(rect.width, rect.height)

    context.saveGState()
    context.setLineWidth(1)

    // Long faint rules, the sheet's own grid.
    Ink.line.withAlphaComponent(0.07).setStroke()
    for _ in 0..<7 {
        let path = NSBezierPath()
        if noise.unit() < 0.5 {
            let y = noise.range(0, rect.height)
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: rect.width, y: y))
        } else {
            let x = noise.range(0, rect.width)
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: rect.height))
        }
        path.setLineDash([9, 11], count: 2, phase: 0)
        path.lineWidth = 1
        path.stroke()
    }

    // Arcs. Big and mostly off the edge, so they read as part of something
    // larger that the crop happens to cut.
    Ink.line.withAlphaComponent(0.10).setStroke()
    for _ in 0..<4 {
        let radius = noise.range(unitSize * 0.45, unitSize * 1.15)
        let centre = CGPoint(x: noise.range(-radius * 0.3, rect.width), y: noise.range(-radius * 0.4, rect.height))
        let circle = NSBezierPath(
            ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        circle.lineWidth = 1
        circle.stroke()
    }

    // Boxes with a dot in them, the way a plan marks a fixing.
    for _ in 0..<9 {
        let size = noise.range(unitSize * 0.05, unitSize * 0.22)
        let box = NSRect(
            x: noise.range(-size * 0.4, rect.width - size * 0.4),
            y: noise.range(-size * 0.4, rect.height - size * 0.4),
            width: size, height: size * noise.range(0.5, 1.1))
        Ink.line.withAlphaComponent(0.09).setStroke()
        let outline = NSBezierPath(rect: box)
        outline.lineWidth = 1
        outline.stroke()
        if noise.unit() < 0.55 {
            Ink.line.withAlphaComponent(0.16).setFill()
            let dot: CGFloat = 3
            NSBezierPath(ovalIn: NSRect(x: box.midX - dot / 2, y: box.midY - dot / 2, width: dot, height: dot))
                .fill()
        }
    }

    // Nodes: a dot with a short leader, which is what makes it read as measured
    // rather than decorated.
    for _ in 0..<11 {
        let point = CGPoint(x: noise.range(0, rect.width), y: noise.range(0, rect.height))
        Ink.line.withAlphaComponent(0.20).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)).fill()
        Ink.line.withAlphaComponent(0.10).setStroke()
        let leader = NSBezierPath()
        leader.move(to: point)
        leader.line(to: CGPoint(x: point.x + noise.range(-70, 70), y: point.y + noise.range(-50, 50)))
        leader.lineWidth = 1
        leader.stroke()
    }

    // Coordinates. Numbers only: any word here would be read, and there is
    // nothing to read.
    let label = NSFont(name: "Avenir Next", size: 9) ?? NSFont.systemFont(ofSize: 9)
    for _ in 0..<14 {
        let text = "\(Int(noise.range(100, 1400))),\(noise.unit() < 0.5 ? "" : "0")\(Int(noise.range(100, 990)))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: label, .foregroundColor: Ink.line.withAlphaComponent(0.22)
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(at: CGPoint(x: noise.range(0, rect.width - 60), y: noise.range(0, rect.height - 12)))
    }
    context.restoreGState()
}

// MARK: - Type

/// SF Pro, which is what the app itself draws in. The App Store slides use
/// Charter because they are posters; this artwork sits next to the product, so
/// it uses the product's typeface. `systemFont` resolves to SF Pro Display above
/// twenty points and SF Pro Text below it, which is the behaviour we want and
/// not something to second-guess by naming a file.
func sf(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func draw(
    _ string: String, font: NSFont, colour: NSColor, at point: CGPoint, kern: CGFloat = 0,
    centred: CGFloat? = nil
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: colour, .kern: kern
    ]
    let text = NSAttributedString(string: string, attributes: attributes)
    let width = text.size().width
    text.draw(at: CGPoint(x: centred.map { $0 - width / 2 } ?? point.x, y: point.y))
}

/// The lockup, from `Resources/Brand`, flattened to white. The shipped artwork
/// has a blue mark beside white letters, which is right on the app's near-black
/// and invisible here: the field it would sit on is the same blue.
func wordmark(centreX: CGFloat, bottom: CGFloat, height: CGFloat) {
    guard let image = NSImage(contentsOfFile: "Resources/Brand/belay-wordmark-dark@3x.png") else {
        FileHandle.standardError.write(Data("no wordmark in Resources/Brand\n".utf8))
        exit(1)
    }
    let white = NSImage(size: image.size)
    white.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSColor.white.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    white.unlockFocus()

    let width = height * image.size.width / image.size.height
    white.draw(in: NSRect(x: centreX - width / 2, y: bottom, width: width, height: height))
}

// MARK: - Chips

/// One promise, as a filled pill with an SF Symbol in front of it.
///
/// Filled and not outlined. Three outlined pills in a row read as a form with
/// three empty fields; the same three filled at low opacity read as labels on
/// the thing above them, which is what they are.
struct Chip {
    var symbol: String
    var label: String
}

func chips(_ items: [Chip], centreX: CGFloat, baseline: CGFloat, scale: CGFloat) {
    let font = sf(15 * scale, .semibold)
    let iconSize = 15 * scale
    let padding = 15 * scale
    let gap = 8 * scale
    let height = 34 * scale
    let between = 10 * scale

    func icon(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let configured = image.withSymbolConfiguration(
            .init(pointSize: iconSize, weight: .semibold)) ?? image
        let white = NSImage(size: configured.size)
        white.lockFocus()
        configured.draw(in: NSRect(origin: .zero, size: configured.size))
        NSColor.white.withAlphaComponent(0.92).set()
        NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
        white.unlockFocus()
        return white
    }

    // Measured first so the row can be centred as one object rather than as
    // three things that happen to be near each other.
    var widths: [CGFloat] = []
    for item in items {
        let text = NSAttributedString(string: item.label, attributes: [.font: font])
        let glyph = icon(item.symbol)
        let iconWidth = glyph.map { $0.size.width * (iconSize / max($0.size.height, 1)) + gap } ?? 0
        widths.append(padding * 2 + iconWidth + ceil(text.size().width))
    }
    let total = widths.reduce(0, +) + between * CGFloat(items.count - 1)

    var x = centreX - total / 2
    for (index, item) in items.enumerated() {
        let box = NSRect(x: x, y: baseline, width: widths[index], height: height)
        NSColor.white.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: box, xRadius: height / 2, yRadius: height / 2).fill()

        var cursor = box.minX + padding
        if let glyph = icon(item.symbol) {
            let width = glyph.size.width * (iconSize / max(glyph.size.height, 1))
            glyph.draw(
                in: NSRect(x: cursor, y: box.midY - iconSize / 2, width: width, height: iconSize))
            cursor += width + gap
        }
        let line = font.ascender - font.descender
        NSAttributedString(
            string: item.label,
            attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.92)]
        ).draw(at: CGPoint(x: cursor, y: box.midY - line / 2 - font.descender * 0.5))
        x += widths[index] + between
    }
}

// MARK: - Rendering

/// `radius` rounds the artwork itself. GitHub strips `style` out of README HTML,
/// so a border-radius written there is dropped in silence and the only rounding
/// that survives is rounding baked into the file.
func render(
    _ name: String, width: CGFloat, height: CGFloat, seed: UInt64, radius: CGFloat = 0,
    body: (NSRect) -> Void
) {
    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if radius > 0 {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    }
    gradient(in: rect)
    blueprint(in: rect, seed: seed)
    body(rect)
    NSGraphicsContext.restoreGraphicsState()

    try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
    let path = "\(output)/\(name).png"
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) — \(Int(width))x\(Int(height))")
}

let promises = [
    Chip(symbol: "person.crop.circle.badge.xmark", label: "No account"),
    Chip(symbol: "eye.slash.fill", label: "No tracking"),
    Chip(symbol: "lock.laptopcomputer", label: "Nothing leaves your Mac"),
]

// The README masthead. Rounded, because it is the first thing on the page and a
// square edge against GitHub's rounded everything else looks like a mistake.
render("masthead", width: 1280, height: 400, seed: 0x5E1F_2A77, radius: 28) { rect in
    wordmark(centreX: rect.midX, bottom: 246, height: 78)
    draw(
        "Keeps your Mac awake while your AI agent works.", font: sf(37, .bold), colour: .white,
        at: CGPoint(x: 0, y: 168), kern: -0.5, centred: rect.midX)
    chips(promises, centreX: rect.midX, baseline: 92, scale: 1)
}

// The Open Graph card. Square on purpose: it is composited onto whatever colour
// Slack, iMessage or Discord happens to use, and a transparent corner there
// comes out as a notch of somebody else's background.
render("og", width: 1280, height: 640, seed: 0x0B3D_9C41) { rect in
    wordmark(centreX: rect.midX, bottom: 404, height: 100)
    draw(
        "Stays awake while", font: sf(62, .bold), colour: .white, at: CGPoint(x: 0, y: 286),
        kern: -1.2, centred: rect.midX)
    draw(
        "your agents work.", font: sf(62, .bold), colour: .white, at: CGPoint(x: 0, y: 196),
        kern: -1.2, centred: rect.midX)
    chips(promises, centreX: rect.midX, baseline: 108, scale: 1.15)
}

// MARK: - Buttons

/// The buttons under the masthead.
///
/// Drawn rather than fetched from shields.io, and the reason is the corner:
/// every shields style is either square or barely rounded, and none of them can
/// be a pill. Rounding them in the README is not an option either, for the same
/// reason the masthead is rounded in the file.
///
/// Rendered at 3x and used at a third of the size, so they stay sharp on a
/// Retina display. The fill is a gradient and not a flat colour: one is a
/// rectangle painted blue, the other is a button.
func button(_ name: String, _ label: String, primary: Bool, glyph: String?) {
    let scale: CGFloat = 3
    let height: CGFloat = 46 * scale
    let radius = height / 2
    let font = sf(17 * scale, .semibold)
    let glyphFont = sf(18 * scale, .medium)

    let padding = 30 * scale
    let gap = 9 * scale
    let text = NSAttributedString(string: label, attributes: [.font: font, .kern: 0.1 * scale])
    let mark = glyph.map { NSAttributedString(string: $0, attributes: [.font: glyphFont]) }
    let markWidth = mark.map { ceil($0.size().width) + gap } ?? 0
    let width = ceil(text.size().width) + markWidth + padding * 2

    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let box = NSRect(x: 0, y: 0, width: width, height: height)
    let pill = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    if primary {
        NSGradient(
            starting: NSColor(srgbRed: 0x3C / 255, green: 0x84 / 255, blue: 1, alpha: 1),
            ending: NSColor(srgbRed: 0x0B / 255, green: 0x57 / 255, blue: 0xE8 / 255, alpha: 1)
        )?.draw(in: pill, angle: -90)
        // The hairline along the top edge is what a real control has and a flat
        // fill does not: light landing on a raised thing.
        NSColor.white.withAlphaComponent(0.28).setStroke()
        let rim = NSBezierPath(
            roundedRect: box.insetBy(dx: 0.8 * scale, dy: 0.8 * scale),
            xRadius: radius, yRadius: radius)
        rim.lineWidth = 1.2 * scale
        rim.stroke()
    } else {
        NSColor.white.withAlphaComponent(0.10).setFill()
        pill.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        let rim = NSBezierPath(
            roundedRect: box.insetBy(dx: 0.8 * scale, dy: 0.8 * scale),
            xRadius: radius, yRadius: radius)
        rim.lineWidth = 1.2 * scale
        rim.stroke()
    }

    let ink = primary ? NSColor.white : NSColor.white.withAlphaComponent(0.86)
    var cursor = padding
    if let mark {
        let line = glyphFont.ascender - glyphFont.descender
        NSAttributedString(
            string: mark.string, attributes: [.font: glyphFont, .foregroundColor: ink]
        ).draw(at: CGPoint(x: cursor, y: height / 2 - line / 2 - glyphFont.descender * 0.55))
        cursor += ceil(mark.size().width) + gap
    }
    let line = font.ascender - font.descender
    NSAttributedString(
        string: label, attributes: [.font: font, .foregroundColor: ink, .kern: 0.1 * scale]
    ).draw(at: CGPoint(x: cursor, y: height / 2 - line / 2 - font.descender * 0.5))
    NSGraphicsContext.restoreGraphicsState()

    try? FileManager.default.createDirectory(
        atPath: "\(output)/buttons", withIntermediateDirectories: true)
    let path = "\(output)/buttons/\(name).png"
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) — \(Int(width / scale))x\(Int(height / scale)) at 1x")
}

// U+F8FF is the Apple logo, which the system fonts carry and nothing else does.
button("download", "Download for macOS", primary: true, glyph: "\u{F8FF}")
button("website", "Website", primary: false, glyph: nil)
