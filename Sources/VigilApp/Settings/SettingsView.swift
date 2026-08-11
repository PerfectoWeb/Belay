import SwiftUI
import VigilProviders
import VigilSettings

/// One pane of the Settings window, rendered on its own.
///
/// There is no switcher in here on purpose. `SettingsWindow` owns the strip in
/// the titlebar and swaps this view's `pane` when the selection changes.
/// SwiftUI's `TabView` renders its tabs into the window toolbar on macOS 26 and
/// folds them into a "more toolbar items" chevron whenever it decides they do
/// not fit — it decided that at every width tried, while also overriding the
/// window size set on the hosting controller. A strip we lay out ourselves
/// cannot do either of those things to us.
struct SettingsView: View {
    var pane: SettingsPane = .general
    @Bindable var settings: SettingsStore
    var state: AppState
    var precise: PreciseDetection
    var targets: [GenericTarget]
    var statistics: UsageStatistics
    var loginItem: LoginItem
    var updates: ReleaseChecker
    var onTargetsChanged: ([GenericTarget]) -> Void

    var body: some View {
        ScrollView(.vertical) { content }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: SettingsPane.width)
    }

    /// The pane without the scroll wrapper.
    ///
    /// The window measures this to decide how tall to be: a `ScrollView` reports
    /// a fitting height of almost nothing, so measuring `body` would size the
    /// window to a sliver.
    @ViewBuilder var content: some View {
        switch pane {
        case .general:
            SettingsStack { GeneralSettingsPane(settings: settings, loginItem: loginItem, updates: updates) }
        case .providers:
            SettingsStack {
                ProvidersSettingsPane(
                    state: state,
                    precise: precise,
                    targets: targets,
                    onTargetsChanged: onTargetsChanged
                )
            }
        case .behaviour:
            SettingsStack { BehaviourSettingsPane(settings: settings) }
        case .notifications:
            SettingsStack { NotificationSettingsPane(settings: settings) }
        case .statistics:
            StatisticsPane(statistics: statistics)
                .frame(width: SettingsPane.width, alignment: .topLeading)
        case .about:
            // Owned elsewhere and brings its own padding, so it is not wrapped.
            AboutPane().frame(width: SettingsPane.width, alignment: .topLeading)
        }
    }
}
