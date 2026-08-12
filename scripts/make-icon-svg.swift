// Writes the app icon as an SVG.
//
//   swift scripts/make-icon-svg.swift <appiconset-dir> <output.svg>
//
// The icon has only ever existed as ten PNGs, so this rebuilds it from the two
// things it is actually made of: a squircle plate with a vertical gradient, and
// the same sparkle path the app draws in the menu bar.
//
// Everything except the corner shape is measured from the 1024 PNG rather than
// assumed, so the vector cannot drift from what ships. The corner is a
// superellipse, which is what macOS uses and what a plain rounded rectangle is
// visibly not: at this radius a circular corner reads as a bubble.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: make-icon-svg.swift <appiconset-dir> <output.svg>")
    exit(1)
}
let master = "\(arguments[1])/icon_512x512@2x.png"
guard let rep = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: master))) else {
    print("could not read \(master)")
    exit(1)
}
let side = CGFloat(rep.pixelsWide)

func colour(_ x: Int, _ y: Int) -> NSColor {
    // A fully transparent pixel comes back tagged grey, and asking a grey
    // colour for its blue component throws rather than returning anything.
    rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .clear
}

/// The plate's box, from the alpha channel.
var plateMinX = rep.pixelsWide, plateMaxX = 0, plateMinY = rep.pixelsHigh, plateMaxY = 0
/// The mark's box, and which subpaths are lit how brightly.
var markMinX = rep.pixelsWide, markMaxX = 0, markMinY = rep.pixelsHigh, markMaxY = 0
for y in 0..<rep.pixelsHigh {
    for x in 0..<rep.pixelsWide {
        let c = colour(x, y)
        if c.alphaComponent > 0.5 {
            plateMinX = min(plateMinX, x)
            plateMaxX = max(plateMaxX, x)
            plateMinY = min(plateMinY, y)
            plateMaxY = max(plateMaxY, y)
        }
        if c.alphaComponent > 0.5, c.blueComponent > 0.55, c.blueComponent - c.redComponent > 0.18 {
            markMinX = min(markMinX, x)
            markMaxX = max(markMaxX, x)
            markMinY = min(markMinY, y)
            markMaxY = max(markMaxY, y)
        }
    }
}
let plateWidth = CGFloat(plateMaxX - plateMinX + 1)
let markWidth = CGFloat(markMaxX - markMinX + 1)
print("plate \(plateMinX),\(plateMinY) \(Int(plateWidth))  mark \(markMinX),\(markMinY) \(Int(markWidth))")

/// The gradient, read from the two ends of the plate rather than guessed.
func hex(_ c: NSColor) -> String {
    String(
        format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
        Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
}
// Twelve rows in, not three: the first few are the antialiased edge and
// sampling them reads the plate several shades lighter than it is.
let top = hex(colour(rep.pixelsWide / 2, plateMinY + 12))
let bottom = hex(colour(rep.pixelsWide / 2, plateMaxY - 12))

/// The three sparkles, with the dim one found rather than assumed: one of them
/// is drawn quieter than the other two and that is the detail that stops the
/// mark reading as three identical stamps.
func brightest(in box: (Int, Int, Int, Int)) -> NSColor {
    // Not `NSColor.black`, which is grey and throws when asked for blue.
    var best = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
    for y in box.1...box.3 {
        for x in box.0...box.2 where colour(x, y).blueComponent > best.blueComponent {
            best = colour(x, y)
        }
    }
    return best
}
let scale = side / 1024
let bigColour = hex(brightest(in: (Int(230 * scale), Int(300 * scale), Int(560 * scale), Int(700 * scale))))
let upperColour = hex(brightest(in: (Int(620 * scale), Int(200 * scale), Int(830 * scale), Int(400 * scale))))
let lowerColour = hex(brightest(in: (Int(600 * scale), Int(560 * scale), Int(830 * scale), Int(780 * scale))))
print("plate \(top) → \(bottom); sparkles big \(bigColour), upper \(upperColour), lower \(lowerColour)")

/// The squircle, as a superellipse. `n = 5` is the exponent macOS's continuous
/// corner sits closest to; sampled finely enough that the curve is smooth at
/// any size the icon is ever drawn.
func squircle(x: CGFloat, y: CGFloat, size: CGFloat) -> String {
    let radius = size / 2
    let centreX = x + radius, centreY = y + radius
    let exponent = 5.0
    var points: [String] = []
    let steps = 512
    for step in 0...steps {
        let angle = Double(step) / Double(steps) * 2 * .pi
        let cosine = cos(angle), sine = sin(angle)
        let px = centreX + radius * CGFloat(copysign(pow(abs(cosine), 2 / exponent), cosine))
        let py = centreY + radius * CGFloat(copysign(pow(abs(sine), 2 / exponent), sine))
        points.append("\(step == 0 ? "M" : "L")\(round(px * 100) / 100) \(round(py * 100) / 100)")
    }
    return points.joined() + "Z"
}

/// The mark, split into its three subpaths so each can carry its own colour.
/// Same `d` string the app parses, so there is one drawing and not two.
let artwork = [
    // Upper small spark.
    "M19.5,24a1,1,0,0,1-.929-.628l-.844-2.113-2.116-.891a1.007,1.007,0,0,1,.035-1.857l2.088-.791"
        + ".837-2.092a1.008,1.008,0,0,1,1.858,0l.841,2.1,2.1.841a1.007,1.007,0,0,1,0,1.858l-2.1.841"
        + "-.841,2.1A1,1,0,0,1,19.5,24Z",
    // The big one.
    "M10,21a2,2,0,0,1-1.936-1.413L6.45,14.54,1.387,12.846a2.032,2.032,0,0,1,.052-3.871L6.462,"
        + "7.441,8.154,2.387A1.956,1.956,0,0,1,10.108,1a2,2,0,0,1,1.917,1.439l1.532,5.015,5.03,1.61a"
        + "2.042,2.042,0,0,1,0,3.872h0l-5.039,1.612-1.612,5.039A2,2,0,0,1,10,21Z",
    // Lower small spark.
    "M20.5,7a1,1,0,0,1-.97-.757l-.357-1.43L17.74,4.428a1,1,0,0,1,.034-1.94l1.4-.325L19.53.757a1,1,"
        + "0,0,1,1.94,0l.354,1.418,1.418.355a1,1,0,0,1,0,1.94l-1.418.355L21.47,6.243A1,1,0,0,1,20.5,7Z"
]

// The artwork is drawn in a 24 unit box. It is placed so that box lands on the
// mark's measured box, which is how the vector inherits the 7% reduction the
// PNGs already carry rather than having it applied twice.
let markScale = markWidth / 24 / scale
let markX = CGFloat(markMinX) / scale
let markY = CGFloat(markMinY) / scale
let colours = [upperColour, bigColour, lowerColour]

let document = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024" \
role="img" aria-label="Belay">
<defs>
<linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="\(top)"/>
<stop offset="1" stop-color="\(bottom)"/>
</linearGradient>
</defs>
<path fill="url(#plate)" d="\(squircle(x: CGFloat(plateMinX) / scale, y: CGFloat(plateMinY) / scale, size: plateWidth / scale))"/>
<g transform="translate(\(round(markX * 100) / 100) \(round(markY * 100) / 100)) scale(\(round(markScale * 10000) / 10000))">
\(artwork.enumerated().map { "<path fill=\"\(colours[$0.offset])\" d=\"\($0.element)\"/>" }.joined(separator: "\n"))
</g>
</svg>
"""
try document.write(toFile: arguments[2], atomically: true, encoding: .utf8)
print("wrote \(arguments[2])")
