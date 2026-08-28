import Foundation
import Network

/// The one place that decides what the hook receiver is reachable from.
///
/// It is its own file so the answer is easy to find and hard to change by
/// accident: `127.0.0.1`, on an ephemeral port, and nothing else. A hook
/// receiver that answered the network would be a remote "keep this Mac awake"
/// button, which is why the restriction is stated twice — once as the required
/// local address and once as the required interface (docs/03 B1).
enum LoopbackListener {
    /// `port` asks for that exact one; `nil` takes whatever is free.
    ///
    /// Asking is the point. The port used to be ephemeral, which meant a new
    /// one on every launch, and every launch left the agent posting to the old
    /// address until it re-read its settings. Worse, an update is exactly when
    /// the old process is still holding the socket, so the new one is *certain*
    /// to land somewhere else: seen in the field on 28 Aug, 61716 becoming
    /// 61717 mid-session, and reproduced here as 49680 becoming 49683 on an
    /// ordinary restart. Keeping the port makes the whole question moot.
    static func make(port: UInt16? = nil) throws -> NWListener {
        let options = NWProtocolTCP.Options()
        options.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: options)
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        do {
            // `on:`, not `requiredLocalEndpoint`. A listener ignores the
            // endpoint in its parameters and binds an ephemeral port anyway:
            // the first version of this asked through the parameters, never
            // failed, and quietly came up somewhere else. It only looked right
            // because a freshly released port is usually handed straight back.
            guard let wanted = port.flatMap({ NWEndpoint.Port(rawValue: $0) }) else {
                return try NWListener(using: parameters)
            }
            return try NWListener(using: parameters, on: wanted)
        } catch {
            throw BridgeError.listenerFailed(error.localizedDescription)
        }
    }
}
