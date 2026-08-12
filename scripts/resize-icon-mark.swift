// Resizes the sparkle inside the app icon without touching the plate.
//
//   swift scripts/resize-icon-mark.swift <master.png> <scale> <appiconset-dir>
//
// The icon has never had a source file; it arrived as ten PNGs. Scaling the
// whole image would shrink the plate along with the mark, and redrawing the
// plate from a guess at its gradient would change the one part nobody asked to
// change. So the mark's box is lifted whole, plate and all, the box is filled
// back in with the gradient rows it covered, and the box is written back
// smaller. The plate inside the moved block is compressed by the same amount,
// which shifts any row of it by at most 22 rows — under two levels out of 255
// on this gradient, and invisible against the plate around it.
//
// Two earlier versions were wrong in ways worth recording, because both looked
// right until they were measured:
//
// Recovering the mark as a layer, by undoing its blend with the plate,
// brightened the one small sparkle that is deliberately dimmer than the other
// two. That difference is what stops the mark reading as three identical stamps.
//
// Compositing through `NSImage.lockFocus` moved every colour: that context
// carries the display's profile, so an sRGB icon came back in Display P3 and
// the mark went from 0.768 red to 0.815. Everything here is arithmetic on
// pixels for that reason, and no drawing context is involved at any point.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let scale = Double(arguments[2]) else {
    print("usage: resize-icon-mark.swift <master.png> <scale> <appiconset-dir>")
    exit(1)
}

guard
    let master = NSBitmapImageRep(
        data: try Data(contentsOf: URL(fileURLWithPath: arguments[1])))
else {
    print("could not read \(arguments[1])")
    exit(1)
}
let side = master.pixelsWide
guard master.pixelsHigh == side else {
    print("the master must be square")
    exit(1)
}
let outputDirectory = arguments[3]

/// One pixel, in the master's own colour space, kept as plain numbers so
/// nothing along the way can decide to convert them.
struct Pixel {
    var r = 0.0
    var g = 0.0
    var b = 0.0
    var a = 0.0

    static func + (lhs: Pixel, rhs: Pixel) -> Pixel {
        Pixel(r: lhs.r + rhs.r, g: lhs.g + rhs.g, b: lhs.b + rhs.b, a: lhs.a + rhs.a)
    }

    static func * (lhs: Pixel, rhs: Double) -> Pixel {
        Pixel(r: lhs.r * rhs, g: lhs.g * rhs, b: lhs.b * rhs, a: lhs.a * rhs)
    }
}

/// Read once. `colorAt` is slow enough that a million calls is a visible pause.
var image: [Pixel] = {
    var pixels = [Pixel](repeating: Pixel(), count: side * side)
    for y in 0..<side {
        for x in 0..<side {
            let c = master.colorAt(x: x, y: y)!
            pixels[y * side + x] = Pixel(
                r: Double(c.redComponent), g: Double(c.greenComponent),
                b: Double(c.blueComponent), a: Double(c.alphaComponent))
        }
    }
    return pixels
}()

func at(_ x: Int, _ y: Int) -> Pixel {
    image[min(side - 1, max(0, y)) * side + min(side - 1, max(0, x))]
}

/// A column inside the plate and clear of the mark, so it reads the gradient
/// and nothing else.
let plateRow: [Pixel] = (0..<side).map { at(side * 140 / 1024, $0) }

/// The mark is far bluer than the plate everywhere, which finds its box without
/// anyone having to say where it is.
var minX = side, maxX = 0, minY = side, maxY = 0
for y in 0..<side {
    for x in 0..<side {
        let p = at(x, y)
        guard p.a > 0.5, p.b > 0.55, p.b - p.r > 0.18 else { continue }
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
    }
}
let markSide = maxX - minX + 1
print("mark box \(minX)…\(maxX) x \(minY)…\(maxY) = \(markSide)x\(maxY - minY + 1)")

/// Area average. At a 7% reduction each output pixel covers a little over one
/// input pixel, so this is close to bilinear and simpler to be sure of.
func sample(_ left: Double, _ top: Double, _ width: Double) -> Pixel {
    let x0 = Int(left.rounded(.down))
    let x1 = max(x0 + 1, Int((left + width).rounded(.up)))
    let y0 = Int(top.rounded(.down))
    let y1 = max(y0 + 1, Int((top + width).rounded(.up)))
    var total = Pixel()
    var count = 0.0
    for y in y0..<y1 {
        for x in x0..<x1 {
            total = total + at(x, y)
            count += 1
        }
    }
    return total * (1 / max(1, count))
}

// The plate, restored: every pixel the mark covered becomes its row's colour.
var rebuilt = image
for y in minY...maxY {
    for x in minX...maxX where at(x, y).a > 0.01 {
        rebuilt[y * side + x] = plateRow[y]
    }
}

// The mark's box, written back smaller and centred on where it was. The block
// brings its own plate with it, which is why the plate under it was restored
// first: the two have to agree at the seam.
let newSide = Int((Double(markSide) * scale).rounded())
let offset = Int(((Double(markSide) - Double(newSide)) / 2).rounded())
let step = Double(markSide) / Double(newSide)
for y in 0..<newSide {
    for x in 0..<newSide {
        let source = sample(
            Double(minX) + Double(x) * step, Double(minY) + Double(y) * step, step)
        guard source.a > 0.001 else { continue }
        rebuilt[(minY + offset + y) * side + minX + offset + x] = source
    }
}
image = rebuilt

/// Every size the appiconset declares, area-averaged from the one master.
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
    ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, pixels) in sizes {
    // Raw bytes, not `setColor`. Setting colours goes through `NSColor`, which
    // wants a colour space, and every combination tried either dropped the
    // alpha or retagged the file. The numbers here are already the master's, so
    // they are written as they are and the file is retagged to match it.
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bitmapFormat: .alphaNonpremultiplied, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
    let bytes = out.bitmapData!
    let ratio = Double(side) / Double(pixels)
    for y in 0..<pixels {
        for x in 0..<pixels {
            let p = sample(Double(x) * ratio, Double(y) * ratio, ratio)
            let index = (y * pixels + x) * 4
            for (offset, value) in [p.r, p.g, p.b, p.a].enumerated() {
                bytes[index + offset] = UInt8(min(255, max(0, (value * 255).rounded())))
            }
        }
    }
    let tagged = out.retagging(with: master.colorSpace) ?? out
    let path = "\(outputDirectory)/\(name).png"
    try tagged.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("\(path) \(pixels)")
}
