import SwiftUI

/// The second time Belay asks for anything, and the last: in the panel, once,
/// right after the app has demonstrably earned it.
///
/// The Statistics row asks under the evidence, in a pane somebody opened on
/// purpose; almost nobody opens it. This one sits in the panel people open a
/// dozen times a day, but it earns its place first: it appears only once Belay
/// has held the Mac through at least an hour of the user's absence, which is
/// the exact moment the app has done the thing it is for. The sentence says
/// that number, so the ask is a receipt rather than a plea.
///
/// The direct build asks for a GitHub star; the App Store build asks for a
/// review in the store it came from. Either answer settles both this row and
/// the Statistics one, through the same key: an app that asks twice is an app
/// that will ask a third time.
///
/// Animates nothing that can change the panel's height.
struct PanelAskCard<Icon: View>: View {
    /// An hour held while away: enough that "did this help" has an answer.
    static var threshold: TimeInterval { 3600 }

    let awayHeld: TimeInterval
    let reason: LocalizedStringKey
    let goTitle: LocalizedStringKey
    let destination: URL?
    @ViewBuilder let icon: () -> Icon

    @State private var isSettled = UserDefaults.standard.bool(forKey: StarAsk.key)
    @State private var hoveringLater = false
    @State private var hoveringGo = false
    /// Full turns the star has made; each hover adds one, and the spring
    /// carries it round with a little overshoot.
    @State private var starTurns: Double = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    static func isEligible(awayHeld: TimeInterval, settled: Bool) -> Bool {
        !settled && awayHeld >= threshold
    }

    /// Debug builds can be asked to show the row regardless, so the design can
    /// be looked at on a Mac that already answered.
    private static var previewForced: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["BELAY_PREVIEW_STAR_ASK"] == "1"
        #else
        return false
        #endif
    }

    private var shows: Bool {
        Self.previewForced || Self.isEligible(awayHeld: awayHeld, settled: isSettled)
    }

    var body: some View {
        if shows, let destination {
            HStack(alignment: .top, spacing: 14) {
                icon()
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 12) {
                    sentence
                    HStack(spacing: 14) {
                        Spacer(minLength: 0)
                        Button("Not now") { settle() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(hoveringLater ? Self.quietLit : Self.quiet)
                            .onHover { inside in
                                hoveringLater = inside
                                Self.pointer(inside)
                            }
                            .animation(.easeInOut(duration: 0.15), value: hoveringLater)
                        Button {
                            openURL(destination)
                            settle()
                        } label: {
                            HStack(spacing: 6) {
                                // Fill plus a round-joined stroke, exactly as the
                                // site draws it: the stroke is what softens the
                                // points into the star David picked.
                                RoundedStar()
                                    .stroke(
                                        Color(red: 0.95, green: 0.79, blue: 0.3),
                                        style: StrokeStyle(lineWidth: 1.1, lineJoin: .round)
                                    )
                                    .background(RoundedStar().fill(Color(red: 0.95, green: 0.79, blue: 0.3)))
                                    .frame(width: 13, height: 13)
                                    // One full turn per hover, on a spring, so it
                                    // overshoots and settles rather than stopping dead.
                                    .rotationEffect(.degrees(starTurns * 360))
                                    .animation(
                                        reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.55),
                                        value: starTurns)
                                Text(goTitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .fixedSize()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.accentColor)
                                    // A touch lighter under the pointer, so the hover
                                    // reads on a flat blue.
                                    .brightness(hoveringGo ? 0.09 : 0))
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            hoveringGo = inside
                            Self.pointer(inside)
                            if inside { starTurns += 1 }
                        }
                        .animation(.easeInOut(duration: 0.15), value: hoveringGo)
                        .overlay(UpdateSparks())
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backdrop)
            )
            .accessibilityElement(children: .contain)
        }
    }

    /// Dark: the mode picker's track (#1C1C1C over the dark panel), which is
    /// what David chose. Light: a wash of the accent instead — the grey track
    /// vanished into the light panel, the tint reads as a card.
    private var backdrop: Color {
        colorScheme == .dark ? Color.primary.opacity(0.06) : Color.accentColor.opacity(0.09)
    }

    /// The receipt in bold, the reason in regular.
    private var sentence: some View {
        let held = ElapsedTime.compact(awayHeld)
        return
            (Text("Belay kept your Mac awake for \(held) while you were away.").bold()
            + Text(verbatim: " ") + Text(reason))
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Not now" in a quiet grey (#8E8E99 on the dark panel, #6A6A74 on the
    /// light one) that lights to full text colour under the pointer.
    private static var quiet: Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0x8E / 255, green: 0x8E / 255, blue: 0x99 / 255, alpha: 1)
                    : NSColor(red: 0x6A / 255, green: 0x6A / 255, blue: 0x74 / 255, alpha: 1)
            })
    }
    /// Under the pointer: white on dark, near-black on light.
    private static var quietLit: Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .white
                    : NSColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x14 / 255, alpha: 1)
            })
    }

    /// The hand cursor over both answers, the way links get it: SwiftUI on
    /// macOS leaves the arrow on plain buttons.
    private static func pointer(_ inside: Bool) {
        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }

    private func settle() {
        UserDefaults.standard.set(true, forKey: StarAsk.key)
        isSettled = true
    }
}

#if BELAY_MAS
/// The App Store build's ask: a review, in the store it was installed from.
struct PanelReviewAsk: View {
    let awayHeld: TimeInterval

    var body: some View {
        PanelAskCard(
            awayHeld: awayHeld,
            reason: "An App Store review helps others find it.",
            goTitle: "Rate it!",
            destination: Branding.appStoreReviewURL
        ) {
            Image(systemName: "star.bubble.fill")
                .font(.system(size: 25))
                .foregroundStyle(.primary)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .accessibilityHidden(true)
        }
    }
}
#else
/// The direct build's ask: a star on the repository.
struct PanelStarAsk: View {
    let awayHeld: TimeInterval

    var body: some View {
        PanelAskCard(
            awayHeld: awayHeld,
            reason: "A GitHub star helps others find it.",
            goTitle: "Star it!",
            destination: Branding.repositoryURL
        ) {
            OctocatMark(size: 30)
        }
    }
}
#endif
