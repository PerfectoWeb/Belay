import Foundation

/// Whether a host is a development site on this Mac or this network, as
/// opposed to a site on the internet.
public enum LocalSite {
    /// Names that never resolve on the public internet: mDNS, the reserved
    /// test names of RFC 2606 and RFC 6762, and what a home router hands out.
    static let suffixes = [".local", ".localhost", ".test", ".internal", ".lan", ".home.arpa"]

    public static func isLocal(host: String) -> Bool {
        let name = host.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !name.isEmpty else { return false }
        if name == "localhost" || name == "::1" { return true }
        if let address = octets(name) { return isPrivate(address) }
        return suffixes.contains { name.hasSuffix($0) && name.count > $0.count }
    }

    /// The hosts a piece of text mentions: those of its URLs, and bare names
    /// like `cytron.local:8888` that carry no scheme.
    public static func hosts(in text: String) -> [String] {
        var found: [String] = []
        for word in text.split(whereSeparator: { $0.isWhitespace || "\"'()<>,".contains($0) }) {
            var token = String(word)
            while let last = token.last, ".:;!?".contains(last) { token.removeLast() }
            guard let host = host(of: token), !found.contains(host) else { continue }
            found.append(host)
        }
        return found
    }

    private static func host(of token: String) -> String? {
        if token.contains("://") {
            guard let url = URLComponents(string: token), let scheme = url.scheme,
                ["http", "https"].contains(scheme.lowercased()), let host = url.host
            else { return nil }
            return host.lowercased()
        }
        let name = token.split(separator: "/", maxSplits: 1).first.map(String.init) ?? token
        let bare = name.split(separator: ":", maxSplits: 1).first.map(String.init) ?? name
        guard looksLikeHost(bare) else { return nil }
        return bare.lowercased()
    }

    /// Anything shaped like a name counts, a file name included. Reading
    /// `notes.txt` as a site that is not local only ever holds an approval
    /// back, and that is the side to err on.
    private static func looksLikeHost(_ name: String) -> Bool {
        if name.lowercased() == "localhost" || octets(name) != nil { return true }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let last = labels.last, last.count >= 2,
            last.allSatisfy(\.isLetter)
        else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return labels.allSatisfy { label in
            !label.isEmpty && label.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    private static func octets(_ name: String) -> [UInt8]? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let values = parts.compactMap { UInt8($0) }
        return values.count == 4 ? values : nil
    }

    private static func isPrivate(_ address: [UInt8]) -> Bool {
        switch (address[0], address[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): true
        case (172, 16...31): true
        default: false
        }
    }
}
