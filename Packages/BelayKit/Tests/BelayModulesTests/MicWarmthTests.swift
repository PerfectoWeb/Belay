import Foundation
import Testing

@testable import BelayModules

@Suite("Microphone keep-warm")
struct MicWarmthTests {
    private func decide(
        isEnabled: Bool = true,
        permission: MicPermission = .granted,
        isOnBattery: Bool = false,
        input: MicKind? = .builtIn,
        rules: MicRules = MicRules()
    ) -> MicWarmth {
        MicWarmth.decide(
            isEnabled: isEnabled, permission: permission, isOnBattery: isOnBattery,
            input: input, rules: rules)
    }

    @Test("Warm when nothing stands in the way")
    func warm() {
        #expect(decide() == .warm)
    }

    @Test("Switched off wins over everything")
    func off() {
        #expect(decide(isEnabled: false, permission: .refused) == .off)
    }

    @Test("No permission, no microphone", arguments: [MicPermission.undecided, .refused])
    func permission(_ permission: MicPermission) {
        #expect(decide(permission: permission) == .needsPermission)
    }

    @Test("The battery pauses it only when asked to")
    func battery() {
        #expect(decide(isOnBattery: true) == .warm)
        #expect(
            decide(isOnBattery: true, rules: MicRules(pausesOnBattery: true)) == .pausedOnBattery)
        #expect(decide(isOnBattery: false, rules: MicRules(pausesOnBattery: true)) == .warm)
    }

    @Test("A Bluetooth microphone is let go unless asked otherwise")
    func bluetooth() {
        #expect(decide(input: .bluetooth) == .pausedForBluetooth)
        #expect(decide(input: .bluetooth, rules: MicRules(leavesBluetoothAlone: false)) == .warm)
        #expect(decide(input: .usb) == .warm)
        #expect(decide(input: .other) == .warm)
        #expect(decide(permission: .refused, input: .bluetooth) == .needsPermission)
    }

    @Test("A record written before the Bluetooth rule gets its default")
    func olderRecord() throws {
        let scratch = try Scratch()
        defer { scratch.discard() }
        scratch.defaults.set(Data(#"{"pausesOnBattery":true}"#.utf8), forKey: MicRules.defaultsKey)
        let rules = MicRules.load(from: scratch.defaults)
        #expect(rules.pausesOnBattery)
        #expect(rules.leavesBluetoothAlone)
    }

    @Test("A Mac with no microphone says so")
    func noMicrophone() {
        #expect(decide(input: nil) == .noMicrophone)
    }

    @Test("Rules survive a round trip and a damaged record")
    func rules() throws {
        let scratch = try Scratch()
        defer { scratch.discard() }
        MicRules(pausesOnBattery: true).save(to: scratch.defaults)
        #expect(MicRules.load(from: scratch.defaults).pausesOnBattery)

        scratch.defaults.set(Data("{}".utf8), forKey: MicRules.defaultsKey)
        #expect(MicRules.load(from: scratch.defaults) == MicRules())
        scratch.defaults.set("nonsense", forKey: MicRules.defaultsKey)
        #expect(MicRules.load(from: scratch.defaults) == MicRules())
    }
}
