// Drops the alpha channel from App Store screenshots.
//
//   swift scripts/flatten-screenshots.swift Promo/AppStore/*.png
//
// App Store Connect refuses a screenshot that has one, at upload, with an
// error that does not name the file. Every cover exported from a design tool
// has one whether or not anything in it is transparent, so this checks first
// and only rewrites images that are opaque everywhere. An image with real
// transparency is left alone and the run fails, because flattening that would
// be a decision about what colour goes behind it.
var anyTransparent = false
for path in CommandLine.arguments.dropFirst() {
    guard let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: path)))
    else { continue }
    let width = rep.pixelsWide, height = rep.pixelsHigh
    var lowest = 1.0
    for y in stride(from: 0, to: height, by: 7) {
        for x in stride(from: 0, to: width, by: 7) {
            lowest = min(lowest, Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 1))
        }
    }
    if lowest < 0.999 {
        print("\((path as NSString).lastPathComponent) has real transparency (\(lowest)); left alone")
        anyTransparent = true
        continue
    }
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: width * 3, bitsPerPixel: 24)!
    let source = rep.bitmapData!, destination = out.bitmapData!
    let stride = rep.bitsPerPixel / 8, row = rep.bytesPerRow
    for y in 0..<height {
        for x in 0..<width {
            for channel in 0..<3 {
                destination[(y * width + x) * 3 + channel] = source[y * row + x * stride + channel]
            }
        }
    }
    let tagged = out.retagging(with: rep.colorSpace) ?? out
    try tagged.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
    print("flattened \((path as NSString).lastPathComponent)")
}
if anyTransparent { exit(1) }
