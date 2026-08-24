import AppKit

/// The drawn fallback marks. Beside `ProviderMark` for the file-length rule.
extension ProviderMark {
    // MARK: - marks

    /// Claude Code. A radiating burst rather than the terminal frame this used
    /// to be: the row is asking "which agent", and a terminal answers "a shell",
    /// which is true of every one of them. Thin rays, so it never reads as
    /// Belay's own four-point sparkle.
    static func burst(_ box: NSRect) {
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
    static func prompt(_ box: NSRect) {
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
    static func braces(_ box: NSRect) {
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
    static func chevrons(_ box: NSRect) {
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

    /// Gemini CLI. Outlined so it never reads as Belay's own filled sparkle.
    static func star(_ box: NSRect) {
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
    static func brackets(_ box: NSRect) {
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

    /// Copilot. The goggles, reduced to a visor with two eyes — recognisably
    /// theirs even when the bundled logo fails to load.
    static func visor(_ box: NSRect) {
        let frame = NSBezierPath(
            roundedRect: NSRect(
                x: box.width * 0.12, y: box.height * 0.3,
                width: box.width * 0.76, height: box.height * 0.44),
            xRadius: box.width * 0.16, yRadius: box.width * 0.16)
        frame.lineWidth = box.width * 0.09
        frame.stroke()
        for side in [-1.0, 1.0] {
            let eye = NSBezierPath(
                roundedRect: NSRect(
                    x: box.midX + CGFloat(side) * box.width * 0.19 - box.width * 0.05,
                    y: box.height * 0.42, width: box.width * 0.1, height: box.height * 0.2),
                xRadius: box.width * 0.05, yRadius: box.width * 0.05)
            eye.fill()
        }
    }

    /// Anything configured by hand.
    static func stack(_ box: NSRect) {
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
}
