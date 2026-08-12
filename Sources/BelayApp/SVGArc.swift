import AppKit
import Foundation

/// The elliptical-arc half of the path parser, kept apart because it is a
/// self-contained piece of geometry and the parser proper is about commands.
///
/// The source artwork rounds every corner with a tiny `a` arc, so a parser that
/// skipped these would square off every shape it drew.
extension Parser {

    /// Endpoint parameterisation to centre parameterisation, then cubics. The
    /// source artwork rounds every corner with a tiny arc, so skipping this
    /// would square off every shape.
    mutating func appendArc(to end: CGPoint, spec: ArcSpec) {
        guard let path = current, spec.radiusX != 0, spec.radiusY != 0 else {
            current?.line(to: flip(end))
            return
        }
        var radiusX = abs(spec.radiusX)
        var radiusY = abs(spec.radiusY)
        let phi = spec.rotation * .pi / 180
        let halfDX = (point.x - end.x) / 2
        let halfDY = (point.y - end.y) / 2
        let x1 = cos(phi) * halfDX + sin(phi) * halfDY
        let y1 = -sin(phi) * halfDX + cos(phi) * halfDY

        let lambda = (x1 * x1) / (radiusX * radiusX) + (y1 * y1) / (radiusY * radiusY)
        if lambda > 1 {
            radiusX *= lambda.squareRoot()
            radiusY *= lambda.squareRoot()
        }

        let sign: CGFloat = spec.isLargeArc == spec.isSweep ? -1 : 1
        let top = max(
            0,
            radiusX * radiusX * radiusY * radiusY - radiusX * radiusX * y1 * y1
                - radiusY * radiusY * x1 * x1)
        let bottom = radiusX * radiusX * y1 * y1 + radiusY * radiusY * x1 * x1
        let factor = bottom == 0 ? 0 : sign * (top / bottom).squareRoot()
        let centreX1 = factor * radiusX * y1 / radiusY
        let centreY1 = -factor * radiusY * x1 / radiusX
        let centre = CGPoint(
            x: cos(phi) * centreX1 - sin(phi) * centreY1 + (point.x + end.x) / 2,
            y: sin(phi) * centreX1 + cos(phi) * centreY1 + (point.y + end.y) / 2)

        let start = angle(1, 0, (x1 - centreX1) / radiusX, (y1 - centreY1) / radiusY)
        var sweep = angle(
            (x1 - centreX1) / radiusX, (y1 - centreY1) / radiusY,
            (-x1 - centreX1) / radiusX, (-y1 - centreY1) / radiusY)
        if !spec.isSweep, sweep > 0 { sweep -= 2 * .pi }
        if spec.isSweep, sweep < 0 { sweep += 2 * .pi }

        emitArcSegments(
            path: path,
            arc: ArcSweep(
                centre: centre, radii: CGPoint(x: radiusX, y: radiusY), phi: phi, start: start,
                sweep: sweep))
    }

    struct ArcSweep {
        var centre: CGPoint
        var radii: CGPoint
        var phi: CGFloat
        var start: CGFloat
        var sweep: CGFloat
    }

    func emitArcSegments(path: NSBezierPath, arc: ArcSweep) {
        let centre = arc.centre
        let radii = arc.radii
        let phi = arc.phi
        let start = arc.start
        let sweep = arc.sweep
        let segments = max(1, Int(ceil(abs(sweep) / (.pi / 2))))
        let step = sweep / CGFloat(segments)
        let alpha = 4.0 / 3 * tan(step / 4)
        var angleStart = start
        var from = point

        for _ in 0..<segments {
            let angleEnd = angleStart + step
            let sinA = sin(angleStart)
            let cosA = cos(angleStart)
            let sinB = sin(angleEnd)
            let cosB = cos(angleEnd)
            let to = CGPoint(
                x: cos(phi) * radii.x * cosB - sin(phi) * radii.y * sinB + centre.x,
                y: sin(phi) * radii.x * cosB + cos(phi) * radii.y * sinB + centre.y)
            let slopeA = CGPoint(
                x: -radii.x * sinA * cos(phi) - radii.y * cosA * sin(phi),
                y: -radii.x * sinA * sin(phi) + radii.y * cosA * cos(phi))
            let slopeB = CGPoint(
                x: -radii.x * sinB * cos(phi) - radii.y * cosB * sin(phi),
                y: -radii.x * sinB * sin(phi) + radii.y * cosB * cos(phi))
            path.curve(
                to: flip(to),
                controlPoint1: flip(CGPoint(x: from.x + alpha * slopeA.x, y: from.y + alpha * slopeA.y)),
                controlPoint2: flip(CGPoint(x: to.x - alpha * slopeB.x, y: to.y - alpha * slopeB.y)))
            angleStart = angleEnd
            from = to
        }
    }

    func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
        let dot = ux * vx + uy * vy
        let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
        var result = acos(min(1, max(-1, length == 0 ? 1 : dot / length)))
        if ux * vy - uy * vx < 0 { result = -result }
        return result
    }
}
