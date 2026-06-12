import Foundation
import Network

/// Forces iOS to actually ask for Local Network permission AND reports what
/// happened at the socket level. URLSession requests to a local server often
/// fail without ever triggering the permission prompt — so the app never
/// appears in Settings → Privacy & Security → Local Network. A raw
/// NWConnection both triggers the prompt reliably and tells us exactly how
/// far the connection got.
enum LocalNetworkPrompter {
    struct ProbeResult {
        let ok: Bool
        let message: String
    }

    static func prime(endpoint: URL, timeout: TimeInterval = 8) async {
        _ = await probe(endpoint: endpoint, timeout: timeout)
    }

    static func probe(endpoint: URL, timeout: TimeInterval = 8) async -> ProbeResult {
        guard let scheme = endpoint.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let hostName = endpoint.host, !hostName.isEmpty else {
            return ProbeResult(ok: false, message:
                "The endpoint “\(endpoint.absoluteString)” doesn't parse. It must look exactly like http://192.168.1.23:11434/v1 — including the http:// part.")
        }
        let portNumber = UInt16(endpoint.port ?? (scheme == "https" ? 443 : 80))
        let port = NWEndpoint.Port(rawValue: portNumber) ?? .http
        let connection = NWConnection(host: NWEndpoint.Host(hostName), port: port, using: .tcp)
        let queue = DispatchQueue(label: "lantern.localnetwork.probe")

        return await withCheckedContinuation { (continuation: CheckedContinuation<ProbeResult, Never>) in
            var finished = false
            var lastWaitError: NWError?
            func finish(_ result: ProbeResult) {
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(ProbeResult(ok: true, message: "socket connected to \(hostName):\(portNumber)"))
                case .failed(let error):
                    finish(ProbeResult(ok: false, message: describe(error, host: hostName, port: portNumber)))
                case .waiting(let error):
                    // Often "permission dialog is up" or "blocked" — keep
                    // waiting until the timeout, but remember why.
                    lastWaitError = error
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                let detail = lastWaitError.map { describe($0, host: hostName, port: portNumber) }
                    ?? "no answer from \(hostName):\(portNumber) after \(Int(timeout))s"
                finish(ProbeResult(ok: false, message: detail))
            }
        }
    }

    private static func describe(_ error: NWError, host: String, port: UInt16) -> String {
        switch error {
        case .dns(let code) where code == -65570:
            return "iOS DENIED Local Network access (policy code -65570). Delete the app, RESTART the iPad, reinstall — that resets the stuck permission so the dialog can appear."
        case .dns(let code):
            return "couldn't look up “\(host)” (DNS \(code)). Use the Mac's IP address instead of a name."
        case .posix(let code) where code == .ECONNREFUSED:
            return "\(host):\(port) refused the connection — the iPad CAN reach the Mac, but nothing is listening on that port. Start Ollama with: OLLAMA_HOST=0.0.0.0 ollama serve"
        case .posix(let code) where code == .EHOSTUNREACH || code == .ENETUNREACH:
            return "no route to \(host) — wrong Wi-Fi network, or Local Network permission is blocking Lantern."
        case .posix(let code) where code == .ETIMEDOUT:
            return "\(host):\(port) timed out — likely the Mac's firewall, or OLLAMA_HOST isn't 0.0.0.0."
        default:
            return "\(error.localizedDescription) (connecting to \(host):\(port))"
        }
    }
}
