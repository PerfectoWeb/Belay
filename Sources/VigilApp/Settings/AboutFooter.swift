import SwiftUI

/// The one link in the footer. Underlined until the pointer is on it, which is
/// the wrong way round for a web page and the right way round here: at 10 pt in
/// a corner, an underline is the only thing that says the name is a link at all,
/// and once the pointer has found it the underline has done its job.
struct HomepageLink: View {
    let url: URL
    @State private var isHovering = false

    var body: some View {
        Link(destination: url) {
            Text(verbatim: "PerfectoWeb")
                .underline(!isHovering)
                .foregroundStyle(isHovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
