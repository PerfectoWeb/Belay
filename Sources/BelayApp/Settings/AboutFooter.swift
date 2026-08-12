import SwiftUI

/// The one link in the footer. Always underlined, because at 10 pt in a corner
/// the underline is the only thing that says the name is a link at all. Hover
/// changes the colour and nothing else: taking the underline away at the moment
/// the pointer arrives reads as the link having been switched off.
struct HomepageLink: View {
    let url: URL
    @State private var isHovering = false

    var body: some View {
        Link(destination: url) {
            Text(verbatim: "PerfectoWeb")
                .underline(true)
                .foregroundStyle(isHovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
