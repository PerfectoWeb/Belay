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
    static func make() throws -> NWListener {
        let options = NWProtocolTCP.Options()
        options.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: options)
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        do {
            return try NWListener(using: parameters)
        } catch {
            throw BridgeError.listenerFailed(error.localizedDescription)
        }
    }
}
