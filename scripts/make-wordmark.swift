// Regenerates the wordmark in Resources/Brand.
//
//   swift scripts/make-wordmark.swift <mark-path-file> <output-dir>
//
// The letters are outlined here rather than left as text so the SVG has no font
// dependency. That means the files cannot be edited by retyping the word: change
// this and rerun it, or the two halves of the lockup will disagree.
// See docs/BRAND.md.
import AppKit
import CoreText

// Outlines the wordmark so the SVG carries no font dependency: SF Pro Rounded
// is not on a web page, and a logo that renders as Times on somebody else's
// machine is not a logo.
func wordPath(_ text: String, size: CGFloat) -> CGPath {
    let font = NSFont.systemFont(ofSize: size, weight: .semibold)
    let rounded = NSFontDescriptor(fontAttributes: [.family: font.familyName ?? ""])
        .withDesign(.rounded).map { NSFont(descriptor: $0, size: size) ?? font } ?? font
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: [.font: rounded]))
    let combined = CGMutablePath()
    for run in (CTLineGetGlyphRuns(line) as! [CTRun]) {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var points = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
        CTRunGetPositions(run, CFRangeMake(0, count), &points)
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        for index in 0..<count {
            guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
            let move = CGAffineTransform(translationX: points[index].x, y: points[index].y)
            combined.addPath(glyph, transform: move)
        }
    }
    return combined
}

func svgPath(_ path: CGPath) -> String {
    var out = ""
    path.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: out += "M\(f(p[0].x)) \(f(p[0].y))"
        case .addLineToPoint: out += "L\(f(p[0].x)) \(f(p[0].y))"
        case .addQuadCurveToPoint: out += "Q\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y))"
        case .addCurveToPoint:
            out += "C\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y))"
        case .closeSubpath: out += "Z"
        @unknown default: break
        }
    }
    return out
}

func f(_ value: CGFloat) -> String { String(format: "%.2f", value) }

let word = wordPath("vigil", size: 36)
let box = word.boundingBoxOfPath
print("WORD \(f(box.minX)) \(f(box.minY)) \(f(box.width)) \(f(box.height))")
print(svgPath(word))

// ---------------------------------------------------------------- the lockup
// Word at 36 semibold rounded, mark at 26 to the ascender, 7pt gap. Chosen by
// looking at nine proportions side by side: below the ascender the mark reads
// as a speck, above it the word starts to look like a caption to the mark.
let markArt = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let markSize: CGFloat = 26
let gap: CGFloat = 7
let pad: CGFloat = 8

let ascender = box.maxY                       // top of "l"
let descender = box.minY                      // bottom of "g"
let width = pad + box.width + gap + markSize + pad
let height = pad + (ascender - descender) + pad

// SVG is y-down; the outlines are y-up from the baseline.
let baseline = pad + ascender
let wordTransform = "translate(\(f(pad - box.minX)) \(f(baseline))) scale(1 -1)"
// The mark artwork is drawn in a 24-unit box, already y-down.
let markScale = markSize / 24
let markX = pad + box.width + gap
let markY = baseline - ascender
let markTransform = "translate(\(f(markX)) \(f(markY))) scale(\(f(markScale)))"

func document(word: String, mark: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(f(width)) \(f(height))" \
    width="\(f(width))" height="\(f(height))" role="img" aria-label="Vigil">
    <path transform="\(wordTransform)" fill="\(word)" d="\(svgPath(self_word))"/>
    <path transform="\(markTransform)" fill="\(mark)" d="\(markArt)"/>
    </svg>
    """
}
let self_word = word
let out = CommandLine.arguments[2]
let blue = "#2379FF"
try! document(word: "#111111", mark: blue)
    .write(toFile: out + "/vigil-wordmark-light.svg", atomically: true, encoding: .utf8)
try! document(word: "#FFFFFF", mark: blue)
    .write(toFile: out + "/vigil-wordmark-dark.svg", atomically: true, encoding: .utf8)
try! document(word: "currentColor", mark: "currentColor")
    .write(toFile: out + "/vigil-wordmark-mono.svg", atomically: true, encoding: .utf8)
print("SVG \(f(width))x\(f(height))")
