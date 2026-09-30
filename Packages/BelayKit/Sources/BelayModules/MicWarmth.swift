import Foundation

/// How the microphone keep-warm is set up.
public struct MicRules: Codable, Equatable, Sendable {
    public static let defaultsKey = "BelayMicKeepWarm"

    /// Let the microphone go cold while the Mac runs on its battery. Off by
    /// default: the people who ask for this module dictate on the sofa too.
    public var pausesOnBattery: Bool
    /// Let a Bluetooth microphone go. Holding one keeps the headphones in call
    /// mode, and what plays through them sounds like a phone line. On by
    /// default: nobody who installs this expects their music to get worse.
    public var leavesBluetoothAlone: Bool

    public init(pausesOnBattery: Bool = false, leavesBluetoothAlone: Bool = true) {
        self.pausesOnBattery = pausesOnBattery
        self.leavesBluetoothAlone = leavesBluetoothAlone
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pausesOnBattery: try values.decodeIfPresent(Bool.self, forKey: .pausesOnBattery)
                ?? false,
            leavesBluetoothAlone: try values.decodeIfPresent(
                Bool.self, forKey: .leavesBluetoothAlone) ?? true)
    }

    public static func load(from defaults: UserDefaults) -> MicRules {
        guard let data = defaults.data(forKey: defaultsKey),
            let rules = try? JSONDecoder().decode(MicRules.self, from: data)
        else { return MicRules() }
        return rules
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}

/// What macOS says about Belay and the microphone.
public enum MicPermission: Sendable, Equatable {
    case undecided
    case granted
    case refused
}

/// How the microphone macOS is set to use is connected. All the rules need
/// to know of it, and all the log may say: its name is somebody's.
public enum MicKind: String, Sendable, Equatable {
    case builtIn
    case usb
    case bluetooth
    case other
}

/// What the keep-warm is doing, and the reason when it is doing nothing.
public enum MicWarmth: Sendable, Equatable {
    case off
    case needsPermission
    case pausedOnBattery
    case pausedForBluetooth
    case noMicrophone
    case warm

    /// The order is the order a person would want to hear about: a refused
    /// permission matters before the battery does, and a missing microphone is
    /// only worth saying once everything else would have let it run. `input`
    /// is nil when macOS has no microphone to offer.
    public static func decide(
        isEnabled: Bool,
        permission: MicPermission,
        isOnBattery: Bool,
        input: MicKind?,
        rules: MicRules
    ) -> MicWarmth {
        guard isEnabled else { return .off }
        guard permission == .granted else { return .needsPermission }
        if rules.pausesOnBattery && isOnBattery { return .pausedOnBattery }
        if rules.leavesBluetoothAlone && input == .bluetooth { return .pausedForBluetooth }
        return input == nil ? .noMicrophone : .warm
    }
}
