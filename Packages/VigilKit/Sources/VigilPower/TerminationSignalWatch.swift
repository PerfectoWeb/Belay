import Foundation
import VigilSupport

/// Releases the assertion when the process is asked to die.
///
/// Invariant 4: SIGTERM and SIGINT must drop the assertion. Without this a
/// `killall Vigil` would leave the assertion live until its timeout expired —
/// survivable, but two minutes of unexplained wakefulness is still a bug.
public actor TerminationSignalWatch {
    private var sources: [DispatchSourceSignal] = []
    private let queue = DispatchQueue(label: "com.perfecto-web.vigil.signals")

    public init() {}

    /// The wiring `VigilApp` actually wants.
    public func install(releasing controller: PowerAssertionController) {
        install { await controller.release() }
    }

    /// Pass `exitsProcess: false` only in tests; production must actually exit.
    public func install(
        signals: [Int32] = [SIGTERM, SIGINT],
        exitsProcess: Bool = true,
        handler: @escaping @Sendable () async -> Void
    ) {
        guard sources.isEmpty else { return }
        for number in signals {
            // DispatchSourceSignal never fires while the default disposition is
            // "terminate the process", so the default has to go first.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                Task {
                    Log.power.notice("Terminating on signal \(number, privacy: .public)")
                    await handler()
                    if exitsProcess { exit(0) }
                }
            }
            source.resume()
            sources.append(source)
        }
    }

    public func cancel() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }
}
