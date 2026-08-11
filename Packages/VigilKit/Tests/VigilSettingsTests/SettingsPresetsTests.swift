import Testing
import VigilCore

@testable import VigilSettings

/// A preset list that cannot express the default is worse than no list: SwiftUI
/// renders an empty pop-up and then writes some other value back, so the user
/// silently ends up with a setting they never chose. That is how the
/// maximum-awake backstop switched itself off on first launch.
@Suite("Settings presets")
struct SettingsPresetsTests {
    @Test("Every default is offered by its own preset list")
    func defaultsAreRepresentable() {
        let policy = AwakePolicy.default
        #expect(
            SettingsPresets.gracePeriods.contains(policy.gracePeriod),
            "grace period default \(policy.gracePeriod) is not in \(SettingsPresets.gracePeriods)"
        )
        #expect(
            SettingsPresets.maxContinuousAwake.contains(policy.maxContinuousAwake),
            "max awake default is not offered by the preset list"
        )
    }

    @Test("Unlimited is offered, and is distinct from every finite choice")
    func unlimitedIsAnOption() {
        #expect(SettingsPresets.maxContinuousAwake.contains(nil))
        let finite = SettingsPresets.maxContinuousAwake.compactMap { $0 }
        #expect(finite.count == SettingsPresets.maxContinuousAwake.count - 1)
        #expect(Set(finite).count == finite.count, "duplicate preset values")
    }

    @Test("Presets are ordered, so the pop-up reads sensibly")
    func presetsAreSorted() {
        #expect(SettingsPresets.gracePeriods == SettingsPresets.gracePeriods.sorted())
        let finite = SettingsPresets.maxContinuousAwake.compactMap { $0 }
        #expect(finite == finite.sorted())
    }
}
