import Foundation

/// The bearer-token check, kept beside the receiver only for the file-length
/// rule.
enum BearerToken {
    /// Folds every byte in before answering, so timing cannot walk the secret
    /// one character at a time. Length is not hidden, only content.
    static func constantTimeEqual(_ lhs: String?, _ rhs: String) -> Bool {
        let left = Array((lhs ?? "").utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}
