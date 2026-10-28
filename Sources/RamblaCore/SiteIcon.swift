import Foundation

/// Where a web site keeps its icon: the overview and the veil draw a browser window with the icon of the site it shows,
/// so that YouTube and GitHub look apart. The places come from the `<link>` tags of the site's page, best first, and
/// then the ones sites use when they say nothing: `/apple-touch-icon.png` and `/favicon.ico`.
public enum SiteIcon {
    public struct Candidate: Equatable, Sendable {
        public let url: URL
        /// Pixels wide, as the page says or as such icons usually are; `scalable` for a drawing (SVG).
        public let size: Int
        /// Made to fill a tile, as a touch icon is, rather than to sit on one.
        public let fillsTile: Bool

        public init(url: URL, size: Int, fillsTile: Bool) {
            self.url = url
            self.size = size
            self.fillsTile = fillsTile
        }
    }

    /// The size a drawing counts as: bigger than any picture.
    public static let scalable = 4096

    /// The host whose icon a page at `url` shows: web pages only.
    public static func host(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    /// The name the overview shows for a site: its host without "www.".
    public static func siteName(ofHost host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The icons of the page at `base` (its address after any redirect) whose start is `html`, and `/apple-touch-icon.png`
    /// and `/favicon.ico` of its host, which may not be there: best first, the largest, a drawing before any picture,
    /// and among the same size the page's own before those two. A mask icon (one color, for pinned tabs) is not one.
    public static func candidates(html: String, base: URL) -> [Candidate] {
        var found: [Candidate] = []
        let head = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.lowerBound]) } ?? html
        for tag in matches(of: #"<link\b[^>]*>"#, in: head) {
            let attributes = self.attributes(of: tag)
            let rel = Set((attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            guard !rel.contains("mask-icon"), let href = attributes["href"], !href.isEmpty else { continue }
            let touch = rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed")
            let fluid = rel.contains("fluid-icon")
            guard touch || fluid || rel.contains("icon"),
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL,
                  host(of: url) != nil else { continue }
            let drawing = attributes["type"]?.lowercased() == "image/svg+xml" || url.path.lowercased().hasSuffix(".svg")
            let size: Int
            if drawing {
                size = scalable
            } else if let sizes = attributes["sizes"]?.lowercased(), let largest = largestSize(in: sizes) {
                size = largest
            } else {
                size = touch ? 180 : fluid ? 512 : 32
            }
            found.append(Candidate(url: url, size: size, fillsTile: touch || fluid))
        }
        if let root = URL(string: "/", relativeTo: base)?.absoluteURL {
            for (path, size, fills) in [("apple-touch-icon.png", 180, true), ("favicon.ico", 32, false)] {
                if let url = URL(string: path, relativeTo: root)?.absoluteURL, !found.contains(where: { $0.url == url }) {
                    found.append(Candidate(url: url, size: size, fillsTile: fills))
                }
            }
        }
        // Largest first; among the same size, in the order found.
        return found.enumerated().sorted {
            $0.element.size != $1.element.size ? $0.element.size > $1.element.size : $0.offset < $1.offset
        }.map(\.element)
    }

    /// The width of the largest size in a `sizes` attribute ("16x16 32x32"); `scalable` for "any".
    private static func largestSize(in sizes: String) -> Int? {
        if sizes.split(separator: " ").contains("any") { return scalable }
        return sizes.split(whereSeparator: \.isWhitespace).compactMap { size in
            size.split(separator: "x").first.flatMap { Int($0) }
        }.max()
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    /// The attributes of a tag, by lowercased name, quoted or not.
    private static func attributes(of tag: String) -> [String: String] {
        let pattern = #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var attributes: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let name = Range(match.range(at: 1), in: tag).map({ tag[$0].lowercased() }) else { continue }
            let value = (2...4).lazy.compactMap { Range(match.range(at: $0), in: tag) }.first.map { String(tag[$0]) }
            if attributes[name] == nil { attributes[name] = value ?? "" }
        }
        return attributes
    }
}
