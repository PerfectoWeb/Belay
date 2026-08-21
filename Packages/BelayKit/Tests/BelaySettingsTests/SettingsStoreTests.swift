import BelayCore
import Foundation
import Observation
import Testing
import os

@testable import BelaySettings

@MainActor
@Suite struct SettingsStoreTests {
    @Test func emptySuiteYieldsThePolicyDefault() throws {
        try withScratchDefaults { scratch in
            let store = SettingsStore(defaults: scratch.defaults)

            #expect(store.policy == AwakePolicy.default)
            #expect(store.launchAtLogin == false)
            #expect(store.hasCompletedOnboarding == false)
            #expect(store.notifyOnAgentNeedsInput)
            #expect(store.notifyOnTaskFinished)
            #expect(store.notifyOnSafetyRelease)
            #expect(store.nightDimmingShowsTimer, "the dim clock ships on")
            #expect(store.taskFinishedThreshold == 300)
            #expect(store.enabledProviders == [.claudeCode])
            #expect(store.isEnabled(.claudeCode))
            #expect(store.isEnabled(.codex) == false)
        }
    }

    @Test func everyPropertySurvivesARestart() throws {
        try withScratchDefaults { scratch in
            let store = SettingsStore(defaults: scratch.defaults)
            store.mode = .alwaysOn
            store.gracePeriod = 45
            store.maxContinuousAwake = 3600
            store.awaitingUserBudget = 600
            store.sessionTTL = 1200
            store.hookFreshnessWindow = 240
            store.batteryFloor = 0.35
            store.shortenGraceInLowPower = false
            store.keepDisplayAwake = true
            store.assertionTimeout = 90
            store.launchAtLogin = true
            store.hasCompletedOnboarding = true
            store.notifyOnAgentNeedsInput = false
            store.notifyOnTaskFinished = false
            store.notifyOnSafetyRelease = false
            store.taskFinishedThreshold = 900
            store.enabledProviders = [.claudeCode, .codex]
            store.nightDimmingShowsTimer = false

            let reopened = SettingsStore(defaults: try scratch.reopened())

            #expect(reopened.policy == store.policy)
            #expect(reopened.mode == .alwaysOn)
            #expect(reopened.gracePeriod == 45)
            #expect(reopened.maxContinuousAwake == 3600)
            #expect(reopened.awaitingUserBudget == 600)
            #expect(reopened.sessionTTL == 1200)
            #expect(reopened.hookFreshnessWindow == 240)
            #expect(reopened.batteryFloor == 0.35)
            #expect(reopened.shortenGraceInLowPower == false)
            #expect(reopened.keepDisplayAwake)
            #expect(reopened.assertionTimeout == 90)
            #expect(reopened.launchAtLogin)
            #expect(reopened.hasCompletedOnboarding)
            #expect(reopened.notifyOnAgentNeedsInput == false)
            #expect(reopened.nightDimmingShowsTimer == false)
            #expect(reopened.notifyOnTaskFinished == false)
            #expect(reopened.notifyOnSafetyRelease == false)
            #expect(reopened.taskFinishedThreshold == 900)
            #expect(reopened.enabledProviders == [.claudeCode, .codex])
        }
    }

    @Test func policyReflectsLiveEdits() throws {
        try withScratchDefaults { scratch in
            let store = SettingsStore(defaults: scratch.defaults)
            store.gracePeriod = 30
            store.mode = .off
            store.keepDisplayAwake = true

            #expect(store.policy.gracePeriod == 30)
            #expect(store.policy.mode == .off)
            #expect(store.policy.keepDisplayAwake)
            #expect(store.policy.effectiveGrace(lowPower: true) == 20)
        }
    }

    @Test func writingNotifiesObservers() throws {
        try withScratchDefaults { scratch in
            let store = SettingsStore(defaults: scratch.defaults)
            let changes = OSAllocatedUnfairLock(initialState: 0)

            withObservationTracking {
                _ = store.gracePeriod
            } onChange: {
                changes.withLock { $0 += 1 }
            }
            store.gracePeriod = 45

            #expect(changes.withLock { $0 } == 1)
            #expect(store.gracePeriod == 45)
        }
    }

    @Test func unknownProviderIdentifiersAreDropped() throws {
        try withScratchDefaults { scratch in
            scratch.defaults.set(["claudeCode", "atlantis"], forKey: "enabledProviders")

            let store = SettingsStore(defaults: scratch.defaults)

            #expect(store.enabledProviders == [.claudeCode])
        }
    }

    /// Deliberately asserts properties rather than repeating the lists.
    /// The previous version pinned them to literals, which meant it passed
    /// happily while the max-awake default was missing from its own preset list
    /// — a test that locks a bug in place instead of catching it.
    /// `SettingsPresetsTests` covers the defaults-are-representable rule.
    @Test func presetsAreWithinTheirBounds() {
        #expect(SettingsPresets.gracePeriods.allSatisfy(SettingsBounds.gracePeriod.contains))
        #expect(
            SettingsPresets.maxContinuousAwake.compactMap { $0 }
                .allSatisfy(SettingsBounds.maxContinuousAwake.contains)
        )
    }
}
