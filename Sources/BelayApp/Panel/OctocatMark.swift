import SwiftUI

/// GitHub's octocat, drawn from David's animated SVG rather than shown as a
/// picture: the body and the two arms are separate paths, so the arms can wave
/// the way the SVG's keyframes have them do, and the eyes are the body's own
/// sub-contours, so one of them can wink.
///
/// The SVG's own transforms are folded into the constants below (its viewBox
/// is 481 by 385; the arm paths live in a far-off coordinate space and the
/// right arm is the left one mirrored), so what is parsed here is the raw path
/// data and nothing else has to be re-derived when the drawing is resized.
///
/// Animates nothing that can change the panel's height: the mark has a fixed
/// frame and only moves inside it.
struct OctocatMark: View {
    var size: CGFloat = 26
    /// A fixed pose instead of the animation, so a test can look at one frame.
    var frozen: Pose?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Pose {
        var arms: Double = 0
        /// 0 is an open eye, 1 a closed one: the lid comes down over the
        /// eye's own contour from the top.
        var lid: Double = 0
        /// 0 is upright, 1 the deepest of a small squash on the wink: the
        /// body sits down a touch and springs back up.
        var squash: Double = 0
    }

    /// Room around the drawing so a waving arm is never cut off by the
    /// canvas's own edge; pulled back out with negative padding, so the mark
    /// takes exactly `size` in the layout.
    private static let halo: CGFloat = 8

    var body: some View {
        let frame = CGSize(width: size, height: size * Artwork.height / Artwork.width)
        Group {
            if let frozen {
                Self.canvas(frozen)
            } else if reduceMotion {
                Self.canvas(Pose())
            } else {
                KeyframeAnimator(initialValue: Pose(), repeating: true) { pose in
                    Self.canvas(pose)
                } keyframes: { _ in
                    // A 3.2 s loop: a wink with a little squash first, then
                    // the ears wag twice on springs and settle with a wobble,
                    // the way a cat that is pleased with itself does it.
                    KeyframeTrack(\.lid) {
                        LinearKeyframe(0, duration: 1.4)
                        CubicKeyframe(1, duration: 0.06)
                        LinearKeyframe(1, duration: 0.15)
                        CubicKeyframe(0, duration: 0.11)
                        LinearKeyframe(0, duration: 1.48)
                    }
                    KeyframeTrack(\.squash) {
                        LinearKeyframe(0, duration: 1.38)
                        SpringKeyframe(1, duration: 0.16, spring: .snappy)
                        SpringKeyframe(0, duration: 0.6, spring: .bouncy)
                        LinearKeyframe(0, duration: 1.06)
                    }
                    KeyframeTrack(\.arms) {
                        LinearKeyframe(0, duration: 1.85)
                        SpringKeyframe(12, duration: 0.14, spring: .snappy)
                        SpringKeyframe(-12, duration: 0.16, spring: .snappy)
                        SpringKeyframe(12, duration: 0.16, spring: .snappy)
                        SpringKeyframe(-12, duration: 0.16, spring: .snappy)
                        SpringKeyframe(0, duration: 0.55, spring: .bouncy)
                        LinearKeyframe(0, duration: 0.18)
                    }
                }
            }
        }
        .frame(width: frame.width + Self.halo * 2, height: frame.height + Self.halo * 2)
        .padding(-Self.halo)
        .accessibilityHidden(true)
    }

    private static func canvas(_ pose: Pose) -> some View {
        Canvas { context, canvasSize in
            let scale = (canvasSize.width - halo * 2) / Artwork.width
            context.translateBy(x: halo, y: halo)
            context.scaleBy(x: scale, y: scale)
            // Opaque on purpose: `.primary` is white at 85 % in the dark panel,
            // and where the arms overlap the body two coats of it read as a
            // patchy, unfinished cat.
            let colour = GraphicsContext.Shading.color(Self.ink)
            // The squash: a little shorter and a little wider, about the feet,
            // so the cat sits down rather than shrinks.
            context.translateBy(x: Artwork.width / 2, y: Artwork.height)
            context.scaleBy(x: 1 + 0.025 * pose.squash, y: 1 - 0.045 * pose.squash)
            context.translateBy(x: -Artwork.width / 2, y: -Artwork.height)
            context.fill(Artwork.body, with: colour)
            if pose.lid > 0 {
                // The eyes are ink on the face's open window, not holes in the
                // head, so a lid is an eraser: the eye's own shape cut out of
                // what has been drawn, from the top down, by as much as the
                // pose says, leaving the face's window showing through.
                // The rim goes too: an erased fill alone leaves the eye's
                // anti-aliased edge behind as a hairline ring, so the eye is
                // also stroked away, and the reveal window is widened by the
                // stroke so the outer half of that ring is not clipped out.
                let rim = 1.5 / scale
                let eye = Artwork.winkEyeBounds.insetBy(dx: -rim, dy: -rim)
                var lid = context
                lid.blendMode = .destinationOut
                lid.clip(
                    to: Path(
                        CGRect(
                            x: eye.minX, y: eye.minY, width: eye.width,
                            height: eye.height * pose.lid)))
                lid.fill(Artwork.winkEye, with: .color(.black))
                lid.stroke(Artwork.winkEye, with: .color(.black), lineWidth: rim * 2)
            }
            for (path, pivot, sign) in [
                (Artwork.leftArm, Artwork.leftPivot, 1.0), (Artwork.rightArm, Artwork.rightPivot, -1.0)
            ] {
                var arm = context
                arm.translateBy(x: pivot.x, y: pivot.y)
                arm.rotate(by: .degrees(pose.arms * sign))
                arm.translateBy(x: -pivot.x, y: -pivot.y)
                arm.fill(path, with: colour)
            }
        }
    }

    /// Solid white on the dark panel, near-black on the light one.
    private static let ink = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .white : NSColor(white: 0.12, alpha: 1)
        })

    private enum Artwork {
        static let width: CGFloat = 481
        static let height: CGFloat = 385
        static let leftPivot = CGPoint(x: 326.5, y: 127.5)
        static let rightPivot = CGPoint(x: 161.1, y: 127.5)

        private static let bodyTransform = CGAffineTransform(translationX: 0.5, y: -63.4)

        // Only `Path`s are kept: they are Sendable, the parser's bezier paths
        // are not, so the body is parsed twice rather than cached once.
        static let body = join(SVGPath.subpaths(bodyData, flipHeight: 0), bodyTransform)
        /// The eye on the viewer's right is the body path's last contour.
        static let winkEye: Path = {
            let parts = SVGPath.subpaths(bodyData, flipHeight: 0)
            return join([parts[parts.count - 1]], bodyTransform)
        }()
        static let winkEyeBounds = winkEye.boundingRect

        static let leftArm = join(
            SVGPath.subpaths(armData, flipHeight: 0),
            CGAffineTransform(translationX: -1655.7, y: -857.1))
        /// The SVG mirrors the same arm path; the mirror is folded in here.
        static let rightArm = join(
            SVGPath.subpaths(armData, flipHeight: 0),
            CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2141.6, ty: -857.1))

        /// `SVGPath` flips y for AppKit; flipping back with a zero height
        /// returns the path to the SVG's own y-down space.
        private static func join(_ parts: [NSBezierPath], _ transform: CGAffineTransform) -> Path {
            var path = Path()
            for part in parts { path.addPath(Path(part.cgPath)) }
            return path.applying(CGAffineTransform(scaleX: 1, y: -1)).applying(transform)
        }

        private static let bodyData =
            "M186.6 329.1c0 20.9-10.9 55.1-36.7 55.1c-25.8 0-36.7-34.2-36.7-55.1c0-20.9 10.9-55.1 "
            + "36.7-55.1c25.8 0 36.7 34.2 36.7 55.1Zm-144.6-164.1c40.8-41 71.2-51.5 115.7-64.6c28.4-8.4 "
            + "58.8-10 88.7-10c27 0 54.4 2.2 80.4 9.2c37.8 10.1 78 25.5 114.7 64.8c28.2 30.2 39 72.3 39 "
            + "114.2c0 31.9-3.2 65.7-17.5 95c-37.9 76.6-142.1 74.8-216.7 74.8c-75.8 0-186.2 2.7-225.6-74.8"
            + "c-14.6-29-20.2-63.1-20.2-95c0-41.9 13.9-81.5 41.5-113.6m374.2 164.1c0-43.9-26.7-82.6-73.5"
            + "-82.6c-18.9 0-37 3.4-56 6c-14.9 2.3-29.8 3.2-45.1 3.2c-15.2 0-30.1-0.9-45.1-3.2c-18.7-2.6"
            + "-37-6-56-6c-46.8 0-73.5 38.7-73.5 82.6c0 87.8 80.4 101.3 150.4 101.3h48.2c70.3 0 150.6-13.4 "
            + "150.6-101.3Zm-82.6-55.1c-25.8 0-36.7 34.2-36.7 55.1c0 20.9 10.9 55.1 36.7 55.1c25.8 0 "
            + "36.7-34.2 36.7-55.1c0-20.9-10.9-55.1-36.7-55.1Z"
        private static let armData =
            "M2097.5 958.3c-30 104.4-209.6 9-115.7-64.6c34.5-27 63.5-36 108.8-36c9.7 19.5 14.6 30.3 "
            + "14.6 51.8c0 16.4-3.1 32.8-7.7 48.8Z"
    }
}

/// The rounded star from the site, as a shape, so the button's star and the
/// site's are the same drawing.
struct RoundedStar: Shape {
    private static let data =
        "M11.5248 2.295C11.5687 2.20646 11.6364 2.13193 11.7203 2.07983C11.8042 2.02772 11.9011 "
        + "2.00011 11.9998 2.00011C12.0986 2.00011 12.1955 2.02772 12.2794 2.07983C12.3633 2.13193 "
        + "12.431 2.20646 12.4748 2.295L14.7848 6.974C14.937 7.28197 15.1617 7.54841 15.4395 7.75045"
        + "C15.7173 7.9525 16.04 8.08411 16.3798 8.134L21.5458 8.89C21.6437 8.90418 21.7357 8.94547 "
        + "21.8113 9.0092C21.887 9.07293 21.9433 9.15655 21.9739 9.25061C22.0045 9.34467 22.0081 "
        + "9.44541 21.9844 9.54144C21.9607 9.63747 21.9107 9.72495 21.8398 9.794L18.1038 13.432C17.8575 "
        + "13.6721 17.6731 13.9685 17.5667 14.2956C17.4602 14.6228 17.4349 14.9709 17.4928 15.31L18.3748 "
        + "20.45C18.3921 20.5478 18.3816 20.6486 18.3443 20.7407C18.3071 20.8328 18.2448 20.9126 18.1644 "
        + "20.971C18.084 21.0294 17.9888 21.064 17.8897 21.0709C17.7906 21.0778 17.6915 21.0567 17.6038 "
        + "21.01L12.9858 18.582C12.6816 18.4222 12.343 18.3388 11.9993 18.3388C11.6557 18.3388 11.3171 "
        + "18.4222 11.0128 18.582L6.39585 21.01C6.30818 21.0564 6.20924 21.0773 6.1103 21.0703C6.01135 "
        + "21.0632 5.91636 21.0286 5.83614 20.9702C5.75592 20.9119 5.69368 20.8322 5.6565 20.7402C5.61933 "
        + "20.6483 5.6087 20.5477 5.62585 20.45L6.50685 15.311C6.56504 14.9717 6.53983 14.6234 6.43338 "
        + "14.296C6.32694 13.9687 6.14245 13.6722 5.89585 13.432L2.15985 9.795C2.08844 9.72603 2.03784 "
        + "9.6384 2.01381 9.54207C1.98978 9.44575 1.99328 9.34462 2.02393 9.25019C2.05457 9.15576 2.11111 "
        + "9.07184 2.18712 9.00798C2.26313 8.94413 2.35555 8.9029 2.45385 8.889L7.61885 8.134C7.9591 "
        + "8.0845 8.28224 7.95306 8.56043 7.75099C8.83863 7.54892 9.06355 7.28227 9.21585 6.974L11.5248 "
        + "2.295Z"
    private static let unit: Path = {
        var path = Path()
        for part in SVGPath.subpaths(data, flipHeight: 0) { path.addPath(Path(part.cgPath)) }
        return path.applying(CGAffineTransform(scaleX: 1, y: -1))
    }()

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return Self.unit.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
    }
}
