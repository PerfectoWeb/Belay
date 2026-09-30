import AVFoundation
import CoreAudio
import Foundation

/// The microphone, held open. Behind a protocol so a test never opens a real
/// one.
protocol MicTap: AnyObject, Sendable {
    /// Opens the microphone macOS is set to use and says its name, or nil
    /// when there is none to open. Opening again lets go of the old one first.
    func open(_ opened: @escaping @Sendable (String?) -> Void)
    func close()
    /// Called when the microphone in use may no longer be the right one: the
    /// input was switched, a device came or went, the session fell over.
    func whenDisturbed(_ handler: @escaping @Sendable () -> Void)
}

/// A capture session whose samples are thrown away as they arrive.
///
/// A microphone that nobody reads is powered down by macOS, and the next app
/// to open it waits for it to start: the first word of a dictation is lost.
/// Reading it and discarding what comes is what keeps it running.
final class CaptureMicTap: NSObject, MicTap, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.perfectoweb.belay.mic", qos: .utility)
    private let samples = DispatchQueue(label: "com.perfectoweb.belay.mic.samples", qos: .background)
    private var session: AVCaptureSession?
    private var disturbed: (@Sendable () -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var inputListener: AudioObjectPropertyListenerBlock?

    private var defaultInput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func whenDisturbed(_ handler: @escaping @Sendable () -> Void) {
        queue.async { self.disturbed = handler }
    }

    func open(_ opened: @escaping @Sendable (String?) -> Void) {
        queue.async {
            self.letGo()
            self.listen()
            guard let device = AVCaptureDevice.default(for: .audio),
                let input = try? AVCaptureDeviceInput(device: device)
            else {
                opened(nil)
                return
            }
            let session = AVCaptureSession()
            let output = AVCaptureAudioDataOutput()
            guard session.canAddInput(input), session.canAddOutput(output) else {
                opened(nil)
                return
            }
            session.addInput(input)
            output.setSampleBufferDelegate(self, queue: self.samples)
            session.addOutput(output)
            session.startRunning()
            self.session = session
            opened(device.localizedName)
        }
    }

    func close() {
        queue.async {
            self.letGo()
            self.unlisten()
        }
    }

    private func letGo() {
        session?.stopRunning()
        session = nil
    }

    private func listen() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [
            AVCaptureDevice.wasConnectedNotification,
            AVCaptureDevice.wasDisconnectedNotification,
            AVCaptureSession.runtimeErrorNotification
        ]
        let center = NotificationCenter.default
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async { self?.disturbed?() }
            }
        }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.queue.async { self?.disturbed?() }
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultInput, queue, listener)
        inputListener = listener
    }

    private func unlisten() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let inputListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &defaultInput, queue, inputListener)
        }
        inputListener = nil
    }
}

extension CaptureMicTap: AVCaptureAudioDataOutputSampleBufferDelegate {
    /// Nothing is done with the sound, and that is the whole point: no copy,
    /// no level meter, no buffer kept.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {}
}
