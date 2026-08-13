// Renders the app icon from its vector source into every size the bundle needs.
//
//   swift scripts/make-appicon.swift Resources/Brand/belay-icon.svg \
//         Resources/Assets.xcassets/AppIcon.appiconset
//
// The icon used to exist only as ten PNGs, and changing anything about it meant
// operating on pixels: an earlier script in this folder separated the mark from
// its plate arithmetically so the mark could be resized without disturbing the
// gradient behind it. That script is gone. `belay-icon.svg` is the icon now,
// and everything else is generated from it.
//
// Notifications, the Dock, Finder, Spotlight and the App Store all draw the
// same `AppIcon`, so there is nothing else to regenerate: macOS resolves the
// notification icon through LaunchServices by bundle identifier and there is no
// separate asset for it.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: make-appicon.swift <icon.svg> <appiconset-dir>")
    exit(1)
}
guard let source = NSImage(contentsOfFile: arguments[1]) else {
    print("could not read \(arguments[1])")
    exit(1)
}
let output = arguments[2]

/// Every size the appiconset declares.
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
    ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, pixels) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: pixels * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    // Rasterised from the vector at every size rather than downsampled from one
    // large bitmap: at 16 px the difference between the two is the difference
    // between a mark and a smudge.
    source.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let tagged = rep.retagging(with: .sRGB) ?? rep
    let path = "\(output)/\(name).png"
    try tagged.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("\(path) \(pixels)")
}
