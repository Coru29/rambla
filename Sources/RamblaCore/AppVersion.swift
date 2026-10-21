import Foundation

/// A release version like "1.2.3" or a tag like "v1.2.3", compared numerically ("1.10" > "1.9").
/// Missing components count as zero and a pre-release suffix ("-beta.1") is ignored.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[..<dash]) }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard let number = Int(piece), number >= 0 else { return nil }
            parts.append(number)
        }
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private static func padded(_ a: AppVersion, _ b: AppVersion) -> ([Int], [Int]) {
        let count = max(a.parts.count, b.parts.count)
        return (a.parts + Array(repeating: 0, count: count - a.parts.count),
                b.parts + Array(repeating: 0, count: count - b.parts.count))
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let (a, b) = padded(lhs, rhs)
        return a == b
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let (a, b) = padded(lhs, rhs)
        return a.lexicographicallyPrecedes(b)
    }
}
