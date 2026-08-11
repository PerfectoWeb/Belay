import AppKit
import Foundation

/// Minimal SVG path parser: only what the source artwork actually uses.
///
/// The point of it is the split into **subpaths**. Each `M` starts a new one,
/// and the sparkle artwork is three separate stars inside a single `d` string —
/// animating them independently means keeping them apart. Nothing here tries to
/// be a general SVG renderer.
enum SVGPath {
    static func subpaths(_ commands: String, flipHeight: CGFloat) -> [NSBezierPath] {
        var parser = Parser(commands: commands, flipHeight: flipHeight)
        return parser.run()
    }
}

/// Everything an arc needs beyond its two endpoints, grouped so the call site
/// stays readable.
struct ArcSpec {
    var radiusX: CGFloat
    var radiusY: CGFloat
    var rotation: CGFloat
    var isLargeArc: Bool
    var isSweep: Bool
}

struct Parser {
    let flipHeight: CGFloat
    private let scanner: Scanner
    private var paths: [NSBezierPath] = []
    var current: NSBezierPath?
    var point: CGPoint = .zero
    private var subpathStart: CGPoint = .zero
    private var lastControl: CGPoint?
    private var previous: Character = " "

    init(commands: String, flipHeight: CGFloat) {
        self.flipHeight = flipHeight
        scanner = Scanner(string: commands)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: ", \n\r\t")
    }

    mutating func run() -> [NSBezierPath] {
        while !scanner.isAtEnd {
            guard let character = scanner.scanCharacter() else { break }
            if character.isNumber || character == "-" || character == "." {
                // An implicit repeat of the previous command: rewind and reuse it.
                scanner.currentIndex = scanner.string.index(before: scanner.currentIndex)
                execute(previous)
                continue
            }
            execute(character)
            // A repeated `M` means `L`, per the SVG spec.
            previous = character == "M" ? "L" : (character == "m" ? "l" : character)
        }
        finishSubpath()
        return paths
    }

    private mutating func execute(_ character: Character) {
        let relative = character.isLowercase
        switch Character(character.uppercased()) {
        case "M": move(relative: relative)
        case "L": line(relative: relative)
        case "H", "V": axisLine(Character(character.uppercased()), relative: relative)
        case "C", "S": cubic(Character(character.uppercased()), relative: relative)
        case "Q": quadratic(relative: relative)
        case "A": arc(relative: relative)
        case "Z": closeSubpath()
        default: break
        }
    }

    // MARK: - commands

    private mutating func move(relative: Bool) {
        guard let target = nextPoint(relative: relative) else { return }
        point = target
        subpathStart = target
        finishSubpath()
        current = NSBezierPath()
        current?.move(to: flip(target))
    }

    private mutating func line(relative: Bool) {
        guard let target = nextPoint(relative: relative) else { return }
        point = target
        current?.line(to: flip(target))
    }

    private mutating func axisLine(_ axis: Character, relative: Bool) {
        guard let value = number() else { return }
        if axis == "H" {
            point.x = relative ? point.x + value : value
        } else {
            point.y = relative ? point.y + value : value
        }
        current?.line(to: flip(point))
    }

    private mutating func cubic(_ kind: Character, relative: Bool) {
        var first: CGPoint
        if kind == "S" {
            // Smooth: the missing control point is the previous one, reflected.
            first = lastControl.map { CGPoint(x: 2 * point.x - $0.x, y: 2 * point.y - $0.y) } ?? point
        } else {
            guard let explicit = nextPoint(relative: relative) else { return }
            first = explicit
        }
        guard let second = nextPoint(relative: relative), let end = nextPoint(relative: relative)
        else { return }
        current?.curve(to: flip(end), controlPoint1: flip(first), controlPoint2: flip(second))
        lastControl = second
        point = end
    }

    private mutating func quadratic(relative: Bool) {
        guard let control = nextPoint(relative: relative), let end = nextPoint(relative: relative)
        else { return }
        let first = CGPoint(
            x: point.x + 2.0 / 3 * (control.x - point.x), y: point.y + 2.0 / 3 * (control.y - point.y))
        let second = CGPoint(
            x: end.x + 2.0 / 3 * (control.x - end.x), y: end.y + 2.0 / 3 * (control.y - end.y))
        current?.curve(to: flip(end), controlPoint1: flip(first), controlPoint2: flip(second))
        point = end
    }

    private mutating func arc(relative: Bool) {
        guard
            let radiusX = number(), let radiusY = number(), let rotation = number(),
            let largeArc = number(), let sweep = number(), let end = nextPoint(relative: relative)
        else { return }
        let spec = ArcSpec(
            radiusX: radiusX, radiusY: radiusY, rotation: rotation,
            isLargeArc: largeArc != 0, isSweep: sweep != 0)
        appendArc(to: end, spec: spec)
        point = end
    }

    private mutating func closeSubpath() {
        current?.close()
        point = subpathStart
    }

    // MARK: - scanning

    private func number() -> CGFloat? {
        guard let value = scanner.scanDouble() else { return nil }
        return CGFloat(value)
    }

    private func nextPoint(relative: Bool) -> CGPoint? {
        guard let deltaX = number(), let deltaY = number() else { return nil }
        return relative ? CGPoint(x: point.x + deltaX, y: point.y + deltaY) : CGPoint(x: deltaX, y: deltaY)
    }

    /// SVG's origin is top-left, AppKit's is bottom-left.
    func flip(_ input: CGPoint) -> NSPoint {
        NSPoint(x: input.x, y: flipHeight - input.y)
    }

    private mutating func finishSubpath() {
        if let current, !current.isEmpty { paths.append(current) }
        current = nil
    }
}
