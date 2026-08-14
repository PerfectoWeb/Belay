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

// MARK: - Type and the lockup

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

/// The lockup, from `Resources/Brand`. Drawn from the shipped artwork rather
/// than redrawn here: a second copy of the wordmark is the first thing to drift.
func wordmark(centreX: CGFloat, bottom: CGFloat, height: CGFloat) {
    guard let image = NSImage(contentsOfFile: "Resources/Brand/belay-wordmark-dark@3x.png") else {
        FileHandle.standardError.write(Data("no wordmark in Resources/Brand\n".utf8))
        exit(1)
    }
    // Flattened to white. The shipped lockup has a blue mark beside white
    // letters, which is right on the app's own near-black and invisible here:
    // the field it would sit on is the same blue.
    let white = NSImage(size: image.size)
    white.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSColor.white.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    white.unlockFocus()

    let width = height * image.size.width / image.size.height
    white.draw(in: NSRect(x: centreX - width / 2, y: bottom, width: width, height: height))
}

func render(_ name: String, width: CGFloat, height: CGFloat, seed: UInt64, body: (NSRect) -> Void) {
    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
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

// MARK: - The two cards

let display = NSFont(name: "Charter-Black", size: 1) != nil ? "Charter-Black" : "Charter-Bold"
func heading(_ size: CGFloat) -> NSFont {
    NSFont(name: display, size: size) ?? NSFont.systemFont(ofSize: size, weight: .heavy)
}
func body(_ size: CGFloat) -> NSFont {
    NSFont(name: "AvenirNext-Medium", size: size) ?? NSFont.systemFont(ofSize: size)
}
func caption(_ size: CGFloat) -> NSFont {
    NSFont(name: "AvenirNext-DemiBold", size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold)
}

let tagline = "Keeps your Mac awake while your AI agent works."
let underline = "No account  ·  No tracking  ·  Nothing leaves your Mac"

// The README masthead. Short, because it sits above the badges and the whole
// block has to be readable before anybody scrolls.
render("masthead", width: 1280, height: 400, seed: 0x5E1F_2A77) { rect in
    wordmark(centreX: rect.midX, bottom: 236, height: 84)
    draw(
        tagline, font: heading(38), colour: .white,
        at: CGPoint(x: 0, y: 160), kern: -0.4, centred: rect.midX)
    // Nudged down from the wordmark by an amount that looks like one gap
    // rather than two things that happen to be near each other.
    draw(
        underline, font: caption(17), colour: NSColor.white.withAlphaComponent(0.72),
        at: CGPoint(x: 0, y: 96), kern: 1.6, centred: rect.midX)
}

// The Open Graph card. Taller, so the tagline gets two lines of room and the
// crop that some clients apply to 2:1 cannot take the wordmark with it.
render("og", width: 1280, height: 640, seed: 0x0B3D_9C41) { rect in
    wordmark(centreX: rect.midX, bottom: 392, height: 104)
    draw(
        "Stays awake while", font: heading(60), colour: .white, at: CGPoint(x: 0, y: 280),
        kern: -0.8, centred: rect.midX)
    draw(
        "your agents work.", font: heading(60), colour: .white, at: CGPoint(x: 0, y: 196),
        kern: -0.8, centred: rect.midX)
    draw(
        underline, font: caption(19), colour: NSColor.white.withAlphaComponent(0.72),
        at: CGPoint(x: 0, y: 120), kern: 1.8, centred: rect.midX)
}

// MARK: - Buttons

/// The buttons under the masthead and in Install.
///
/// Drawn rather than fetched from shields.io, and the reason is the corner: every
/// shields style is either square or barely rounded, and none of them can be a
/// pill. Rounding them in the README is not an option either — GitHub strips
/// `style` out of README HTML, so a border-radius written there is dropped in
/// silence. A picture of a button is the only rounded button GitHub will show.
///
/// Rendered at 3x and used at a third of the size, so they stay sharp on a
/// Retina display.
func button(_ name: String, _ label: String, fill: NSColor?, ink: NSColor, glyph: String?) {
    let scale: CGFloat = 3
    let height: CGFloat = 44 * scale
    let radius = height / 2
    let font = NSFont(name: "AvenirNext-DemiBold", size: 17 * scale)
        ?? NSFont.systemFont(ofSize: 17 * scale, weight: .semibold)

    let text = (glyph.map { "\($0)  " } ?? "") + label
    let measured = NSAttributedString(string: text, attributes: [.font: font, .kern: 0.2 * scale])
    let width = ceil(measured.size().width) + 34 * scale * 2

    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let box = NSRect(x: 0, y: 0, width: width, height: height)
    let pill = NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
    if let fill {
        fill.setFill()
        pill.fill()
    } else {
        // The secondary button is an outline. A filled grey next to a filled
        // blue reads as two choices of equal weight, and they are not.
        NSColor(srgbRed: 0.55, green: 0.58, blue: 0.65, alpha: 0.55).setStroke()
        pill.lineWidth = 1.6 * scale
        pill.stroke()
    }

    // Centred by giving the label a box exactly one line tall and placing that
    // box, rather than by nudging a baseline. `draw(in:)` puts the first line at
    // the top of whatever rect it is handed, so a full-height rect in an
    // unflipped context hangs the text off the top of the pill.
    let lineHeight = font.ascender - font.descender
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    NSAttributedString(
        string: text,
        attributes: [
            .font: font, .foregroundColor: ink, .kern: 0.2 * scale,
            .paragraphStyle: paragraph
        ]
    ).draw(in: NSRect(x: 0, y: (height - lineHeight) / 2, width: width, height: lineHeight))
    NSGraphicsContext.restoreGraphicsState()

    try? FileManager.default.createDirectory(atPath: "\(output)/buttons", withIntermediateDirectories: true)
    let path = "\(output)/buttons/\(name).png"
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) — \(Int(width / scale))x\(Int(height / scale)) at 1x")
}

let accent = NSColor(srgbRed: 0x1F / 255, green: 0x6B / 255, blue: 1, alpha: 1)
let quiet = NSColor(srgbRed: 0.62, green: 0.66, blue: 0.74, alpha: 1)

button("download", "Download for macOS", fill: accent, ink: .white, glyph: "\u{2193}")
button("website", "Website", fill: nil, ink: quiet, glyph: nil)
button("download-now", "Download Now", fill: accent, ink: .white, glyph: "\u{2193}")
button("site", "Website", fill: nil, ink: quiet, glyph: "\u{2192}")
