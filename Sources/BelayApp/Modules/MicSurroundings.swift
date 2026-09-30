import AVFoundation
import AppKit
import BelayModules
import CoreAudio
import IOKit.ps

/// What the keep-warm asks of the Mac around it: the permission, the power
/// source, and the moments worth looking again.
@MainActor
struct MicSurroundings {
    var permission: () -> MicPermission
    var ask: (@escaping @MainActor (Bool) -> Void) -> Void
    var isOnBattery: () -> Bool
    /// How the microphone macOS is set to use is connected, or nil without one.
    var inputKind: () -> MicKind?
    /// Calls back when the power source or the input changed, or the Mac woke
    /// up, until the returned closure is called.
    var watch: (@escaping @MainActor () -> Void) -> () -> Void

    static let real = MicSurroundings(
        permission: {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .undecided
            default: .refused
            }
        },
        ask: { answered in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in answered(granted) }
            }
        },
        isOnBattery: {
            let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
            let source = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
            return source == kIOPMBatteryPowerKey
        },
        inputKind: { DefaultInput.kind },
        watch: { changed in
            let power = PowerSourceWatch(changed)
            let input = DefaultInput.Watch(changed)
            let woke = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { changed() }
            }
            return {
                power.cancel()
                input.cancel()
                NSWorkspace.shared.notificationCenter.removeObserver(woke)
            }
        }
    )

    static func openSettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}

/// Told by the system when the Mac goes on or off its battery, instead of
/// asking on a timer.
@MainActor
private final class PowerSourceWatch {
    private let changed: @MainActor () -> Void
    private var source: CFRunLoopSource?

    init(_ changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let watch = Unmanaged<PowerSourceWatch>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { watch.changed() }
        }
        source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    func cancel() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }
}

/// The input macOS is set to use, as CoreAudio knows it.
enum DefaultInput {
    nonisolated(unsafe) private static var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    static var kind: MicKind? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var input = address
        guard AudioObjectGetPropertyData(system, &input, 0, nil, &size, &device) == noErr,
            device != kAudioObjectUnknown
        else { return nil }
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var type = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &type, 0, nil, &size, &transport) == noErr else {
            return .other
        }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        default: return .other
        }
    }

    /// Told by CoreAudio when another input takes over.
    @MainActor
    final class Watch {
        private var listener: AudioObjectPropertyListenerBlock?

        init(_ changed: @escaping @MainActor () -> Void) {
            let listener: AudioObjectPropertyListenerBlock = { _, _ in
                MainActor.assumeIsolated { changed() }
            }
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &DefaultInput.address, .main, listener)
            self.listener = listener
        }

        func cancel() {
            guard let listener else { return }
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &DefaultInput.address, .main, listener)
            self.listener = nil
        }
    }
}
