import Foundation
import Network

/// Forces iOS to actually ask for Local Network permission. URLSession
/// requests to a local server often just fail without ever triggering the
/// prompt — so the app never even appears in Settings → Privacy & Security →
/// Local Network. Opening a raw NWConnection to the configured host reliably
/// makes the system show the prompt and register the app in that list.
enum LocalNetworkPrompter {
    /// Touches the endpoint's host/port and waits briefly — long enough for
    /// the permission dialog to appear and be answered on first run.
    static func prime(endpoint: URL, timeout: TimeInterval = 8) async {
        guard let hostName = endpoint.host else { return }
        let port = NWEndpoint.Port(rawValue: UInt16(endpoint.port ?? 80)) ?? .http
        let connection = NWConnection(host: NWEndpoint.Host(hostName), port: port, using: .tcp)
        let queue = DispatchQueue(label: "lantern.localnetwork.prime")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            func finish() {
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume()
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    finish()
                default:
                    // .preparing / .waiting can mean "permission dialog is
                    // up" — keep waiting until the timeout.
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish()
            }
        }
    }
}
