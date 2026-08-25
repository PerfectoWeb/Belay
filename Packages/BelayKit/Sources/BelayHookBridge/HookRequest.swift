import BelayCore
import BelaySupport
import Foundation

/// Just enough HTTP/1.1 to accept one POST from Claude Code.
///
/// A real server would be the wrong shape here: this listener speaks to exactly
/// one client, on loopback, with one route. Only the two header fields Belay
/// acts on are lifted out — the rest of the head, like the body, is never
/// collected into anything that outlives the parse.
struct HookRequest {
    let method: String
    let path: String
    let authorization: String?
    let body: Data
}

/// The only replies the receiver ever sends. All of them are empty and all of
/// them close the connection: there is nothing Claude Code wants back from us.
enum HookResponse: Int {
    case accepted = 204
    case badRequest = 400
    case unauthorized = 401
    case notFound = 404
    case tooLarge = 413

    var head: String {
        let reason: String
        switch self {
        case .accepted: reason = "No Content"
        case .badRequest: reason = "Bad Request"
        case .unauthorized: reason = "Unauthorized"
        case .notFound: reason = "Not Found"
        case .tooLarge: reason = "Payload Too Large"
        }
        return "HTTP/1.1 \(rawValue) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    }
}

enum HookRequestParser {
    enum Outcome {
        case incomplete
        case malformed
        case request(HookRequest)
    }

    /// Beyond this we stop reading and answer anyway. `PostToolUse` bodies carry
    /// tool output, so a file read can make one genuinely large; the cap is only
    /// here so a runaway or hostile client cannot make Belay grow without bound.
    static let maximumBytes = 4 * 1024 * 1024

    private static let separator = Data("\r\n\r\n".utf8)

    /// The two header fields the receiver reads, pulled out so `parse` stays
    /// inside the complexity rule.
    private static func parseHeaders(
        _ lines: [String]
    ) -> (authorization: String?, declaredLength: Int) {
        var authorization: String?
        var declaredLength = 0
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch name {
            case "authorization": authorization = value
            case "content-length": declaredLength = Int(value) ?? 0
            default: break
            }
        }
        return (authorization, declaredLength)
    }

    static func parse(_ buffer: Data) -> Outcome {
        guard let headEnd = buffer.range(of: separator) else { return .incomplete }
        guard
            let head = String(
                bytes: buffer[buffer.startIndex..<headEnd.lowerBound], encoding: .utf8)
        else { return .malformed }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .malformed }

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .malformed }

        let headers = parseHeaders(lines)
        // A negative length is a malformed header, not a short read: without
        // this guard `offsetBy: -1` below lands bodyEnd before bodyStart and
        // the body slice traps — a crash any unauthenticated local POST could
        // trigger, taking the sleep assertion down with the process.
        guard headers.declaredLength >= 0 else { return .malformed }
        let authorization = headers.authorization
        let declaredLength = headers.declaredLength

        let bodyStart = headEnd.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        guard available >= declaredLength else { return .incomplete }
        let bodyEnd = buffer.index(bodyStart, offsetBy: declaredLength)

        return .request(
            HookRequest(
                method: String(requestLine[0]).uppercased(),
                path: String(requestLine[1]),
                authorization: authorization,
                body: Data(buffer[bodyStart..<bodyEnd])))
    }
}

extension HookReceiver {
    /// Who is posting, read off the URL the installer wrote. Claude Code's
    /// hooks carry no `agent` item — theirs predate the idea — so its absence
    /// means Claude, and an unknown value falls back the same way rather than
    /// inventing a provider.
    static func provider(inPath path: String) -> ProviderID {
        guard let components = URLComponents(string: path),
            let agent = components.queryItems?.first(where: { $0.name == "agent" })?.value
        else { return .claudeCode }
        switch agent {
        case "codex": return .codex
        case "cline": return .cline
        default: return .claudeCode
        }
    }

    /// One posted body, decoded by whoever's vocabulary the URL names, into
    /// at most one signal. Logging happens here so the receiver stays under
    /// its own roof: names, activities and counts — never the body (R9).
    static func agentSignal(path: String, body: Data, at now: Date) -> ActivitySignal? {
        let provider = provider(inPath: path)
        if provider == .cline {
            guard let signal = ClineHookEnvelope.signal(path: path, body: body, at: now) else {
                return nil
            }
            EventLog.note("hook cline \(signal.session) -> \(signal.activity)")
            return signal
        }
        guard let envelope = try? JSONDecoder().decode(HookEnvelope.self, from: body),
            let signal = envelope.signal(at: now, provider: provider)
        else { return nil }
        let bg = envelope.backgroundTasks ?? -1
        EventLog.note("hook \(envelope.eventName) \(signal.session) -> \(signal.activity) bg=\(bg)")
        return signal
    }
}
