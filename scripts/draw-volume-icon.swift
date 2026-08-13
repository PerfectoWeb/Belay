// Draws the disk image's volume icon: an external drive in Belay's blue with
// the mark on its face, in the shape Finder has always used for a mounted
// volume. Everything is vector, so the 1024 render downsamples cleanly to the
// 16pt entry in the sidebar.

import AppKit

let side: CGFloat = 1024

func brand(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

/// The drive body: a rounded rectangle tapered a little towards the top, which
/// is what reads as "seen slightly from above" without drawing real perspective.
func driveBody() -> NSBezierPath {
    let top: CGFloat = 962, bottom: CGFloat = 78
    let topInset: CGFloat = 92, bottomInset: CGFloat = 66
    let radius: CGFloat = 78

    let path = NSBezierPath()
    let topLeft = CGPoint(x: topInset, y: top)
    let topRight = CGPoint(x: side - topInset, y: top)
    let bottomRight = CGPoint(x: side - bottomInset, y: bottom)
    let bottomLeft = CGPoint(x: bottomInset, y: bottom)

    path.move(to: CGPoint(x: topLeft.x + radius, y: topLeft.y))
    path.line(to: CGPoint(x: topRight.x - radius, y: topRight.y))
    path.appendArc(from: topRight, to: bottomRight, radius: radius)
    path.line(to: CGPoint(x: bottomRight.x, y: bottomRight.y + radius))
    path.appendArc(from: bottomRight, to: bottomLeft, radius: radius)
    path.line(to: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y))
    path.appendArc(from: bottomLeft, to: topLeft, radius: radius)
    path.line(to: CGPoint(x: topLeft.x, y: topLeft.y - radius))
    path.appendArc(from: topLeft, to: topRight, radius: radius)
    path.close()
    return path
}

/// One four-pointed star with concave sides, the shape used in the app icon.
///
/// `waist` is how far the control points sit from the centre, as a fraction of
/// the arm. It is the whole character of the mark: near zero gives four thin
/// spikes, and the app icon's star is plump, so this wants to be high. The arms
/// take separate lengths because that star is wider than it is tall.
func sparkle(centre: CGPoint, rx: CGFloat, ry: CGFloat, waist: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let points = [
        CGPoint(x: centre.x, y: centre.y + ry),
        CGPoint(x: centre.x + rx, y: centre.y),
        CGPoint(x: centre.x, y: centre.y - ry),
        CGPoint(x: centre.x - rx, y: centre.y),
    ]
    path.move(to: points[0])
    for index in 0..<4 {
        let from = points[index], to = points[(index + 1) % 4]
        path.curve(to: to,
                   controlPoint1: CGPoint(x: centre.x + (from.x - centre.x) * waist,
                                          y: centre.y + (from.y - centre.y) * waist),
                   controlPoint2: CGPoint(x: centre.x + (to.x - centre.x) * waist,
                                          y: centre.y + (to.y - centre.y) * waist))
    }
    path.close()
    return path
}

let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()
let context = NSGraphicsContext.current!.cgContext
context.setShouldAntialias(true)

let body = driveBody()

// The drive sits on a soft shadow, so it reads as an object on the desktop
// rather than a sticker.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34,
                  color: brand(0x0A2C6B, 0.34).cgColor)
brand(0x2C79FF).setFill()
body.fill()
context.restoreGState()

// Face. Lighter at the top left, deeper at the bottom right: one light source,
// consistently applied, is most of what makes a flat shape look moulded.
context.saveGState()
body.addClip()
let face = NSGradient(colors: [brand(0x5B93FF), brand(0x2668E8), brand(0x1450C8)],
                      atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
face.draw(in: NSRect(x: 0, y: 0, width: side, height: side), angle: -72)

// The moulded left edge of the case.
let seam = NSGradient(colors: [brand(0xFFFFFF, 0.30), brand(0xFFFFFF, 0)],
                      atLocations: [0, 1], colorSpace: .sRGB)!
seam.draw(in: NSRect(x: 60, y: 60, width: 96, height: side - 120), angle: 0)

// A darker foot, where the case turns away from the light.
let foot = NSGradient(colors: [brand(0x0B3EA6, 0.55), brand(0x0B3EA6, 0)],
                      atLocations: [0, 1], colorSpace: .sRGB)!
foot.draw(in: NSRect(x: 0, y: 68, width: side, height: 150), angle: 90)

// Top highlight, one thin line along the upper rim.
let rim = NSGradient(colors: [brand(0xFFFFFF, 0.34), brand(0xFFFFFF, 0)],
                     atLocations: [0, 1], colorSpace: .sRGB)!
rim.draw(in: NSRect(x: 0, y: side - 190, width: side, height: 130), angle: -90)
context.restoreGState()

// A hairline edge stops the shape dissolving into a light desktop background.
context.saveGState()
brand(0x0E42A8, 0.55).setStroke()
body.lineWidth = 3
body.stroke()
context.restoreGState()

// The mark. Three stars, the same arrangement as the app icon: one large, two
// small, the smaller pair in a paler blue so the big one stays the subject.
// Filling a thin star and stroking the same path with a round join is what
// gives the arms their weight and blunts the four tips. Widening the curve
// instead just straightens the sides until the star is a diamond.
func drawSparkle(_ path: NSBezierPath, weight: CGFloat, colour: NSColor) {
    colour.setFill()
    colour.setStroke()
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    path.lineWidth = weight
    path.fill()
    path.stroke()
}

// Chosen off a contact sheet of the pair: 0.28 keeps a real taper in the arms
// and a quarter of the arm as weight blunts the tips without swelling them
// into a plus sign.
let waist: CGFloat = 0.28
let heft: CGFloat = 0.25

let centre = CGPoint(x: side * 0.455, y: side * 0.525)
drawSparkle(sparkle(centre: centre, rx: 218, ry: 200, waist: waist),
            weight: 218 * heft, colour: .white)

let pale = brand(0xB9D3FF)
drawSparkle(sparkle(centre: CGPoint(x: centre.x + 248, y: centre.y + 184), rx: 78, ry: 78, waist: waist),
            weight: 78 * heft, colour: pale)
drawSparkle(sparkle(centre: CGPoint(x: centre.x + 214, y: centre.y - 210), rx: 64, ry: 64, waist: waist),
            weight: 64 * heft, colour: pale)

// The activity light, bottom left, the detail that says "drive" more than the
// silhouette does.
context.saveGState()
context.setShadow(offset: .zero, blur: 22, color: brand(0xFFFFFF, 0.85).cgColor)
brand(0xF2F7FF).setFill()
NSBezierPath(ovalIn: NSRect(x: 132, y: 126, width: 30, height: 30)).fill()
context.restoreGState()

image.unlockFocus()

let target = URL(fileURLWithPath: CommandLine.arguments[1])
let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: target)
print("wrote \(target.path)")
