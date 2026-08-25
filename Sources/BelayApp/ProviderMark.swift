import AppKit
import BelayCore
import SwiftUI

/// Small monochrome marks identifying which agent a session belongs to.
///
/// The real vendor mark is used where Belay ships one, because the row exists to
/// answer "who is working" and an invented shape answers "something is". They are
/// bundled as template assets: single-path SVGs with vector data preserved, so
/// they stay 1:1 with the original at any size and take the row's own colour
/// rather than a baked-in brand one. See NOTICE.md — every one of them belongs
/// to its owner and is used here only to identify their software.
///
/// The drawn marks below are the fallback, and still the answer for anything
/// Belay has no logo for: a preset with no artwork gets a neutral shape rather
/// than a wrong logo or an empty row.
@MainActor
enum ProviderMark {
    /// Every vendor mark Belay ships. Asset names are the preset ids, prefixed —
    /// so adding a logo is adding an imageset, with no code change.
    ///
    /// Tested by name because the failure mode is silent: rename an imageset and
    /// `NSImage(named:)` returns nil, the drawn fallback appears, and the app
    /// keeps working while looking wrong.
    static let bundledLogos = [
        "chatgpt", "claude", "cline", "codex", "copilot", "gemini", "github", "opencode", "pi"
    ]

    static func image(for provider: ProviderID, preset: String? = nil, size: CGFloat = 15) -> NSImage {
        switch provider {
        case .claudeCode:
            return logo("logo-claude", size: size) ?? draw(size: size, burst)
        case .codex:
            return logo("logo-codex", size: size) ?? draw(size: size, braces)
        case .cline:
            return logo("logo-cline", size: size) ?? draw(size: size, brackets)
        case .copilot:
            return logo("logo-copilot", size: size) ?? draw(size: size, visor)
        case .generic:
            // A generic session names the preset it came from, so "Other agents"
            // still shows Gemini's mark when it is Gemini that is running.
            guard let preset else { return draw(size: size, stack) }
            return image(preset: preset, size: size)
        }
    }

    /// Presets are identified by their string id (`GenericPreset.all`), which is
    /// also the asset name. A preset with no artwork falls back to a drawn mark,
    /// and one Belay has never heard of falls back to the generic one.
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
            case "copilot": visor(context)
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
