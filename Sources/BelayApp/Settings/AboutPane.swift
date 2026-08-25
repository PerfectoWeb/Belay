import AppKit
import BelayChannel
import SwiftUI

/// The About pane.
///
/// Warm, but restrained — the animation is one slowly drifting starfield behind
/// a breathing mark, and it exists only while this pane is on screen. A settings
/// window that keeps animating in the background is exactly the kind of thing
/// this app is supposed to be the opposite of.
struct AboutPane: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `.inactive` covers a window on another Space, behind another app, or
    /// simply not focused. The sky stops there, and starts again when you look.
    @Environment(\.controlActiveState) private var activeState
    @State private var appeared = false
    @State private var pointer: [String: CGPoint] = [:]

    private var isAnimating: Bool { !reduceMotion && activeState != .inactive }

    var body: some View {
        VStack(spacing: 0) {
            hero
            Divider()
            body(padding: 20)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }

    private var hero: some View {
        ZStack {
            // A fixed night sky rather than the window background. The hero is
            // the one place in the app that commits to a look of its own, and
            // the alternative — semantic colours — put black stars on white.
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.09, green: 0.10, blue: 0.15)
                ],
                startPoint: .top, endPoint: .bottom)

            Starfield(animated: isAnimating)
                .frame(height: 150)
                .clipped()

            VStack(spacing: 10) {
                // Two spacers rather than a top padding and one: the free space
                // splits evenly, so the lockup sits centred in what is left
                // above the promises instead of hanging from the top edge.
                Spacer(minLength: 12)
                BelayWordmark(size: 38, animated: isAnimating)
                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.10), in: Capsule())
                Spacer(minLength: 12)
                promises
            }
            .padding(.top, 8)
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 226)
    }

    /// One translated sentence, split around the company name at display time so
    /// the name can answer the pointer. The catalogue still holds one sentence:
    /// a translator handed "© 2026", a name and "MIT licensed" as three strings
    /// has nothing left to arrange, and the name is a proper noun that survives
    /// translation unchanged.
    @ViewBuilder private var copyright: some View {
        let sentence = String(
            localized: "© 2026 PerfectoWeb. Free & source-available. Built by geeks, for geeks.")
        let parts = sentence.components(separatedBy: Self.owner)
        if parts.count == 2, let url = Branding.homepageURL {
            HStack(spacing: 0) {
                Text(verbatim: parts[0])
                HomepageLink(url: url)
                Text(verbatim: parts[1])
            }
        } else {
            Text(verbatim: sentence)
        }
    }

    private static let owner = "PerfectoWeb"

    private func body(padding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // The one sentence that has to land. Primary weight, not caption
            // grey: everything under it is supporting material.
            Text("Keeps your Mac awake exactly as long as your agent is working.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            privacyNote

            AboutLinks()

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                copyright
                // The marks in the session list belong to other people. Saying so
                // inside the app, not only in the repository, is the point:
                // nobody reads a NOTICE file before installing something.
                Text("All product names and logos are trademarks of their respective owners.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The promise that costs the most to break, so it follows the headline
    /// directly. No icon and no plate: a shield glyph beside it made a plain
    /// commitment look like a marketing badge, and the sentence is better than
    /// the badge.
    private var privacyNote: some View {
        Text(PrivacyPromise.forThisChannel)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Stated plainly, because these are the reasons to trust a utility that
    /// watches your agent, and they are worth more than a feature list.
    ///
    /// Inside the hero rather than under it, with no fill of their own — the
    /// night sky is the container. A band with its own plate sitting directly
    /// beneath a framed hero read as two boxes arguing about which one was the
    /// header.
    /// "1.0.0 (1) · Direct download". See `DistributionChannel.displayName`.
    private var versionLine: String {
        let channel = DistributionChannel.current.displayName
        return String(localized: "Version \(Branding.version) (\(Branding.build)) · \(channel)")
    }

    private var promises: some View {
        HStack(spacing: 12) {
            ForEach(Promise.all) { promise in
                HStack(spacing: 6) {
                    Image(systemName: promise.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(promise.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                // Fill, no stroke. On the night sky an outline is a second
                // frame inside a frame; a translucent plate just lifts the tile
                // off the background, which is all it has to do.
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                // Liquid, not a lamp. A soft blob under the pointer, chased by a
                // quick spring so it stretches towards the cursor and settles
                // behind it, with the tile lifting very slightly under it. The
                // spring has to be fast: at the previous timing the highlight
                // trailed the cursor and read as stuck rather than as fluid.
                .overlay {
                    GeometryReader { proxy in
                        let point = pointer[promise.id]
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [.white.opacity(0.30), .white.opacity(0.06), .clear],
                                    center: .center, startRadius: 0, endRadius: 46)
                            )
                            .frame(width: 108, height: 74)
                            .blur(radius: 12)
                            .position(
                                x: point?.x ?? proxy.size.width / 2,
                                y: point?.y ?? proxy.size.height / 2
                            )
                            .opacity(point == nil ? 0 : 1)
                            .animation(.spring(response: 0.22, dampingFraction: 0.62), value: point)
                            .animation(.easeOut(duration: 0.2), value: point == nil)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .allowsHitTesting(false)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.white.opacity(pointer[promise.id] == nil ? 0 : 0.18), lineWidth: 1)
                        .animation(.easeOut(duration: 0.2), value: pointer[promise.id] == nil)
                )
                .scaleEffect(pointer[promise.id] == nil ? 1 : 1.015)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pointer[promise.id] == nil)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): pointer[promise.id] = location
                    case .ended: pointer[promise.id] = nil
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 6)
    }

    /// `LocalizedStringResource` rather than `String`: `Text(String)` is
    /// verbatim, so plain titles here silently shipped untranslated. It is also
    /// `Sendable`, which `LocalizedStringKey` is not, so it can live in a
    /// static table.
    private struct Promise: Identifiable, Sendable {
        let id: String
        let title: LocalizedStringResource
        let symbol: String

        static let all = [
            Promise(id: "free", title: "Free", symbol: "gift"),
            Promise(id: "ads", title: "No ads", symbol: "hand.raised"),
            Promise(id: "tracking", title: "No tracking", symbol: "eye.slash"),
            Promise(id: "offline", title: "Local only", symbol: "wifi.slash")
        ]
    }
}
