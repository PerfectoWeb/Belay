import AppKit
import SwiftUI
import VigilCore

/// Small monochrome marks identifying which agent a session belongs to.
///
/// The real vendor mark is used where Vigil ships one, because the row exists to
/// answer "who is working" and an invented shape answers "something is". They are
/// bundled as template assets: single-path SVGs with vector data preserved, so
/// they stay 1:1 with the original at any size and take the row's own colour
/// rather than a baked-in brand one. See NOTICE.md — every one of them belongs
/// to its owner and is used here only to identify their software.
///
/// The drawn marks below are the fallback, and still the answer for anything
/// Vigil has no logo for: a preset with no artwork gets a neutral shape rather
/// than a wrong logo or an empty row.
@MainActor
enum ProviderMark {
    /// Every vendor mark Vigil ships. Asset names are the preset ids, prefixed —
    /// so adding a logo is adding an imageset, with no code change.
    ///
    /// Tested by name because the failure mode is silent: rename an imageset and
    /// `NSImage(named:)` returns nil, the drawn fallback appears, and the app
    /// keeps working while looking wrong.
    static let bundledLogos = ["chatgpt", "claude", "cline", "codex", "gemini"]

    static func image(for provider: ProviderID, preset: String? = nil, size: CGFloat = 15) -> NSImage {
        switch provider {
        case .claudeCode:
            return logo("logo-claude", size: size) ?? draw(size: size, burst)
        case .codex:
            return logo("logo-codex", size: size) ?? draw(size: size, braces)
        case .generic:
            // A generic session names the preset it came from, so "Other agents"
            // still shows Gemini's mark when it is Gemini that is running.
            guard let preset else { return draw(size: size, stack) }
            return image(preset: preset, size: size)
        }
    }

    /// Presets are identified by their string id (`GenericPreset.all`), which is
    /// also the asset name. A preset with no artwork falls back to a drawn mark,
    /// and one Vigil has never heard of falls back to the generic one.
    static func image(preset id: String, size: CGFloat = 15) -> NSImage {
        if let logo = logo("logo-\(id)", size: size) { return logo }
        return draw(size: size) { context in
            // Reached only when the bundled logo fails to load. Each named
            // preset falls back to its own shape rather than to the neutral
            // one, so a dropped asset degrades instead of erasing the identity.
            switch id {
            case "aider": chevrons(context)
            case "gemini": star(context)
            case "cline": brackets(context)
            case "codex", "chatgpt": braces(context)
            case "claude": burst(context)
            case "terminal": prompt(context)
            default: stack(context)
            }
        }
    }

    /// A bundled vendor mark, scaled into a square box without distorting it —
    /// not every logo is square, and stretching one to fit is exactly the kind
    /// of "close enough" that makes a brand unrecognisable.
    private static func logo(_ name: String, size: CGFloat) -> NSImage? {
        guard let source = NSImage(named: name), source.size.width > 0, source.size.height > 0 else {
            return nil
        }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { box in
            let scale = min(box.width / source.size.width, box.height / source.size.height)
            let fitted = NSSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(
                in: NSRect(
                    x: box.midX - fitted.width / 2, y: box.midY - fitted.height / 2,
                    width: fitted.width, height: fitted.height))
            return true
        }
        // Set after drawing: the source draws its own black artwork, and the
        // alpha of the result is what AppKit recolours.
        image.isTemplate = true
        return image
    }

    // MARK: - marks

    /// Claude Code. A radiating burst rather than the terminal frame this used
    /// to be: the row is asking "which agent", and a terminal answers "a shell",
    /// which is true of every one of them. Thin rays, so it never reads as
    /// Vigil's own four-point sparkle.
    private static func burst(_ box: NSRect) {
        let centre = NSPoint(x: box.midX, y: box.midY)
        let outer = box.width * 0.42
        let inner = box.width * 0.13
        for step in 0..<8 {
            let angle = CGFloat(step) * .pi / 4
            let ray = NSBezierPath()
            ray.move(to: NSPoint(x: centre.x + cos(angle) * inner, y: centre.y + sin(angle) * inner))
            ray.line(to: NSPoint(x: centre.x + cos(angle) * outer, y: centre.y + sin(angle) * outer))
            ray.lineWidth = box.width * (step.isMultiple(of: 2) ? 0.13 : 0.09)
            ray.lineCapStyle = .round
            ray.stroke()
        }
        let core = box.width * 0.075
        NSBezierPath(
            ovalIn: NSRect(x: centre.x - core, y: centre.y - core, width: core * 2, height: core * 2)
        ).fill()
    }

    /// A plain CLI, for anything watched by process name alone.
    private static func prompt(_ box: NSRect) {
        let frame = NSBezierPath(
            roundedRect: box.insetBy(dx: box.width * 0.06, dy: box.width * 0.14),
            xRadius: box.width * 0.18, yRadius: box.width * 0.18)
        frame.lineWidth = box.width * 0.09
        frame.stroke()

        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: box.width * 0.3, y: box.height * 0.62))
        chevron.line(to: NSPoint(x: box.width * 0.46, y: box.height * 0.5))
        chevron.line(to: NSPoint(x: box.width * 0.3, y: box.height * 0.38))
        chevron.lineWidth = box.width * 0.09
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.stroke()

        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: box.width * 0.54, y: box.height * 0.37))
        bar.line(to: NSPoint(x: box.width * 0.72, y: box.height * 0.37))
        bar.lineWidth = box.width * 0.09
        bar.lineCapStyle = .round
        bar.stroke()
    }

    /// Codex CLI.
    private static func braces(_ box: NSRect) {
        for side in [-1.0, 1.0] {
            let brace = NSBezierPath()
            let column = box.midX + CGFloat(side) * box.width * 0.26
            // Negated: the ends of a brace point inward, the cusp outward.
            let reach = -CGFloat(side) * box.width * 0.13
            brace.move(to: NSPoint(x: column + reach, y: box.height * 0.16))
            brace.curve(
                to: NSPoint(x: column, y: box.midY),
                controlPoint1: NSPoint(x: column, y: box.height * 0.24),
                controlPoint2: NSPoint(x: column, y: box.height * 0.36))
            brace.curve(
                to: NSPoint(x: column + reach, y: box.height * 0.84),
                controlPoint1: NSPoint(x: column, y: box.height * 0.64),
                controlPoint2: NSPoint(x: column, y: box.height * 0.76))
            brace.lineWidth = box.width * 0.1
            brace.lineCapStyle = .round
            brace.stroke()
        }
    }

    /// Aider.
    private static func chevrons(_ box: NSRect) {
        for offset in [-0.16, 0.14] {
            let chevron = NSBezierPath()
            let column = box.midX + CGFloat(offset) * box.width
            chevron.move(to: NSPoint(x: column - box.width * 0.1, y: box.height * 0.7))
            chevron.line(to: NSPoint(x: column + box.width * 0.1, y: box.midY))
            chevron.line(to: NSPoint(x: column - box.width * 0.1, y: box.height * 0.3))
            chevron.lineWidth = box.width * 0.1
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.stroke()
        }
    }

    /// Gemini CLI. Outlined so it never reads as Vigil's own filled sparkle.
    private static func star(_ box: NSRect) {
        let path = NSBezierPath()
        let radius = box.width * 0.38
        let waist = radius * 0.32
        let centre = NSPoint(x: box.midX, y: box.midY)
        for step in 0..<4 {
            let angle = CGFloat(step) * .pi / 2
            let tip = NSPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            let next = angle + .pi / 4
            let inner = NSPoint(x: centre.x + cos(next) * waist, y: centre.y + sin(next) * waist)
            if step == 0 { path.move(to: tip) } else { path.line(to: tip) }
            path.line(to: inner)
        }
        path.close()
        path.lineWidth = box.width * 0.09
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// Cline.
    private static func brackets(_ box: NSRect) {
        for side in [-1.0, 1.0] {
            let bracket = NSBezierPath()
            let column = box.midX + CGFloat(side) * box.width * 0.28
            bracket.move(to: NSPoint(x: column - CGFloat(side) * box.width * 0.12, y: box.height * 0.18))
            bracket.line(to: NSPoint(x: column, y: box.height * 0.18))
            bracket.line(to: NSPoint(x: column, y: box.height * 0.82))
            bracket.line(to: NSPoint(x: column - CGFloat(side) * box.width * 0.12, y: box.height * 0.82))
            bracket.lineWidth = box.width * 0.1
            bracket.lineCapStyle = .round
            bracket.lineJoinStyle = .round
            bracket.stroke()
        }
        let dot = box.width * 0.09
        NSBezierPath(
            ovalIn: NSRect(x: box.midX - dot, y: box.midY - dot, width: dot * 2, height: dot * 2)
        ).fill()
    }

    /// Anything configured by hand.
    private static func stack(_ box: NSRect) {
        for level in 0..<3 {
            let baseline = box.height * (0.28 + 0.22 * CGFloat(level))
            let width = box.width * (0.52 - 0.06 * CGFloat(level))
            let bar = NSBezierPath(
                roundedRect: NSRect(
                    x: box.midX - width / 2, y: baseline, width: width, height: box.height * 0.1),
                xRadius: box.height * 0.05, yRadius: box.height * 0.05)
            bar.fill()
        }
    }

    private static func draw(size: CGFloat, _ body: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            body(rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
extension Image {
    init(providerMark provider: ProviderID, preset: String? = nil, size: CGFloat = 15) {
        self.init(nsImage: ProviderMark.image(for: provider, preset: preset, size: size))
    }

    /// `size` is the size the mark will be *drawn* at. Rendering at one size and
    /// resizing to another upscales a raster and softens a logo that is the
    /// whole point of the column it sits in.
    init(presetMark id: String, size: CGFloat = 15) {
        self.init(nsImage: ProviderMark.image(preset: id, size: size))
    }
}
