import Foundation

/// The generic provider's editor, described as data so the Providers pane can be
/// generated rather than hand-written (docs/02).
///
/// `ProviderDescriptor` carries what every provider has — name, summary, symbol,
/// whether it supports precise detection — but a provider the *user configures*
/// also needs its form described, and the descriptor has nowhere to put that.
/// Rather than widen a type six other things depend on, the shape lives beside
/// the provider that owns it: the pane reads `GenericProvider.descriptor` for
/// the row and `GenericConfigurationField.all` for the editor, and adding a
/// field here changes no UI code. See the M5 report for why this is a seam worth
/// watching rather than a clean win.
public struct GenericConfigurationField: Sendable, Identifiable {
    /// The control to render, paired with the property it writes. The key path
    /// is what keeps the UI generic: the pane binds to it without knowing which
    /// field it is looking at.
    public enum Input: Sendable {
        case text(any WritableKeyPath<GenericTarget, String> & Sendable)
        case optionalText(any WritableKeyPath<GenericTarget, String?> & Sendable)
        case folder(any WritableKeyPath<GenericTarget, URL?> & Sendable)
        case seconds(
            any WritableKeyPath<GenericTarget, TimeInterval> & Sendable,
            range: ClosedRange<TimeInterval>)
    }

    public let id: String
    public let title: String
    /// Plain language, shown under the control. Says what the setting does to
    /// detection, not what the property is called.
    public let explanation: String
    public let input: Input
    /// A field the user can leave empty and still have a working target.
    public let isOptional: Bool
}

extension GenericConfigurationField {
    public static let all: [GenericConfigurationField] = [
        GenericConfigurationField(
            id: "displayName",
            title: "Name",
            explanation: "What this shows as in the menu bar list.",
            input: .text(\.displayName),
            isOptional: false),
        GenericConfigurationField(
            id: "watchedFolder",
            title: "Watch folder",
            explanation: """
                Any file changing under this folder counts as the agent working. \
                Vigil reads that files changed, never what is in them.
                """,
            input: .folder(\.watchedFolder),
            isOptional: true),
        GenericConfigurationField(
            id: "processName",
            title: "Process name",
            explanation: """
                Used only to notice the agent has exited. A running process never \
                keeps the Mac awake on its own.
                """,
            input: .optionalText(\.processName),
            isOptional: true),
        GenericConfigurationField(
            id: "webhookIdentifier",
            title: "Webhook name",
            explanation: """
                The name a tool sends as session= when it calls Vigil's local \
                hook URL. Leave empty unless you have wired one up.
                """,
            input: .optionalText(\.webhookIdentifier),
            isOptional: true),
        GenericConfigurationField(
            id: "inferredIdleAfter",
            title: "Treat as finished after",
            explanation: """
                Quiet time before Vigil decides the turn ended. Agents go silent \
                mid-tool-call, so shorter is not better.
                """,
            input: .seconds(\.inferredIdleAfter, range: GenericTarget.quietPeriodRange),
            isOptional: false)
    ]
}
