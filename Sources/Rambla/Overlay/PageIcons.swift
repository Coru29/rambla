import AppKit
import RamblaCore

/// The site a browser window shows, for the overview and the veil to draw the window with instead of the browser: the
/// site's icon on a tile with the browser's in its corner, the site's color and its name, so that YouTube and GitHub
/// look apart. The page comes from the window (`WindowManager.readPage`), read again a moment after its title changes;
/// the icon comes from the site itself (`SiteIconFetcher`), asked once per site while Rambla runs and kept only in
/// memory, so that nothing of what a private window showed stays on disk.
@MainActor
final class PageIcons {
    /// How a browser window looks: the site's name, and its icon and color once the site's icon came.
    struct Look {
        let site: String
        let icon: NSImage?
        let tint: NSColor?
    }

    /// The browsers whose windows show a page: a web area with its address in their Accessibility tree.
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.beta",
        "com.google.Chrome.canary", "org.chromium.Chromium", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly", "com.kagi.kagimacOS",
        "app.zen-browser.zen", "com.duckduckgo.macos.browser",
    ]

    /// Seconds after a title changes before the page is read: the page that changed it has its address by then.
    private static let readDelay = 0.5
    /// A read with no answer by then is given up (the app hangs, or its worker is gone), and may be asked again.
    private static let readTimeout = 3.0
    /// A site where no icon was found is asked again after this long: the network may have been down.
    private static let retryMissing = 10 * 60.0

    private let readPage: (WindowID, @escaping (URL?) -> Void) -> Void
    /// Called once a page is read or a site's icon comes: what shows the windows draws them again.
    var changed: (() -> Void)?

    /// By window: its title when its page was read, and the host of that page (nil: no web page).
    private var pages: [WindowID: (title: String, host: String?)] = [:]
    /// The windows being read, since when, and those to read once their title settles.
    private var reading: [WindowID: CFAbsoluteTime] = [:]
    private var waiting: [WindowID: Int] = [:]
    private var lastWait = 0
    /// The sites' icons by host, the hosts being asked, and those with none, since when.
    private var icons: [String: SiteImage] = [:]
    private var fetching: Set<String> = []
    private var missing: [String: CFAbsoluteTime] = [:]
    /// The tiles drawn, by host and browser.
    private var tiles: [String: NSImage] = [:]

    init(readPage: @escaping (WindowID, @escaping (URL?) -> Void) -> Void) {
        self.readPage = readPage
    }

    /// How window `id` of the app `bundleID`, titled `title`, looks: nil when it is not a browser's, it shows no web
    /// page, or its page is not known for that title yet (it is read now). `browserIcon` goes in the tile's corner.
    func look(of id: WindowID, bundleID: String?, title: String, browserIcon: NSImage?) -> Look? {
        guard let bundleID, Self.browsers.contains(bundleID) else { return nil }
        guard let page = pages[id], page.title == title else {
            read(id, title: title)
            return nil
        }
        guard let host = page.host else { return nil }
        let site = SiteIcon.siteName(ofHost: host)
        guard let icon = icons[host] else {
            fetch(host)
            return Look(site: site, icon: nil, tint: nil)
        }
        let key = host + " " + bundleID
        let tile = tiles[key] ?? SiteIconTile.image(icon, browser: browserIcon)
        tiles[key] = tile
        return Look(site: site, icon: tile, tint: icon.tint)
    }

    /// The title of window `id` changed to `title`: a browser window's page is read again once it settles.
    func titleChanged(_ id: WindowID, bundleID: String?, title: String) {
        guard let bundleID, Self.browsers.contains(bundleID) else { return }
        lastWait += 1
        let mine = lastWait
        waiting[id] = mine
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.waiting[id] == mine else { return }
                self.waiting[id] = nil
                self.read(id, title: title)
            }
        }
    }

    private func read(_ id: WindowID, title: String) {
        let now = CFAbsoluteTimeGetCurrent()
        if let since = reading[id], now - since < Self.readTimeout { return }
        reading[id] = now
        readPage(id) { [weak self] url in
            MainActor.assumeIsolated {
                guard let self, self.reading[id] == now else { return }
                self.reading[id] = nil
                let host = url.flatMap(SiteIcon.host(of:))
                self.pages[id] = (title, host)
                if let host { self.fetch(host) }
                self.changed?()
            }
        }
    }

    private func fetch(_ host: String) {
        let now = CFAbsoluteTimeGetCurrent()
        guard icons[host] == nil, !fetching.contains(host),
              missing[host].map({ now - $0 > Self.retryMissing }) ?? true else { return }
        fetching.insert(host)
        Task { [weak self] in
            let found = await SiteIconFetcher.icon(of: host)
            guard let self else { return }
            self.fetching.remove(host)
            if let found, let image = SiteImage(found) {
                self.icons[host] = image
                self.missing[host] = nil
                self.changed?()
            } else {
                self.missing[host] = CFAbsoluteTimeGetCurrent()
            }
        }
    }
}

/// A site's icon, ready to draw.
struct SiteImage {
    let image: NSImage
    /// Made to fill a tile (a touch icon).
    let fillsTile: Bool
    /// The width of its largest picture in pixels; 0 for a drawing, sharp at any size.
    let pixels: Int
    /// The site's color, from its icon, as an app's comes from its own (`OverviewItem.tint`).
    let tint: NSColor

    init?(_ found: SiteIconFetcher.Icon) {
        guard let image = NSImage(data: found.data), image.size.width > 0 else { return nil }
        self.image = image
        fillsTile = found.fillsTile
        pixels = image.representations.map(\.pixelsWide).max() ?? 0
        tint = OverviewItem.tint(of: image)
    }
}

/// A site's icon as the overview and the veil draw an app's: on a white rounded tile, which a touch icon fills, with the
/// browser's icon small in its corner. It is drawn anew at each size, so it is sharp at any.
enum SiteIconTile {
    static func image(_ site: SiteImage, browser: NSImage?) -> NSImage {
        NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
            let tile = rect.insetBy(dx: rect.width * 0.09, dy: rect.height * 0.09)
            let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
            NSGraphicsContext.saveGraphicsState()
            NSColor.white.setFill()
            shape.fill()
            shape.addClip()
            if site.fillsTile {
                site.image.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                hints: hints)
            } else {
                // A favicon sits in the middle, at most twice as many pixels wide as it has: stretched further, it blurs.
                var side = tile.width * 0.62
                if site.pixels > 0 {
                    let scale = abs(NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 1)
                    side = min(side, CGFloat(site.pixels) * 2 / max(scale, 0.01))
                }
                let inner = NSRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
                site.image.draw(in: inner, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                hints: hints)
            }
            NSGraphicsContext.restoreGraphicsState()
            if let browser {
                let side = rect.width * 0.44
                browser.draw(in: NSRect(x: rect.maxX - side, y: rect.minY, width: side, height: side), from: .zero,
                             operation: .sourceOver, fraction: 1, respectFlipped: true, hints: hints)
            }
            return true
        }
    }
}

/// Asks a web site for its icon: its page for where it keeps it (`SiteIcon.candidates`), then the first of those that
/// is a picture or a drawing. No cookies, nothing kept on disk.
enum SiteIconFetcher {
    struct Icon: Sendable {
        let data: Data
        let fillsTile: Bool
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Rambla",
        ]
        return URLSession(configuration: configuration)
    }()

    /// The icon of the site at `host`, or nil when it has none that Rambla can draw, or did not answer.
    static func icon(of host: String) async -> Icon? {
        guard let page = URL(string: "https://\(host)/") else { return nil }
        var html = ""
        var base = page
        if let (data, response) = try? await session.data(from: page), succeeded(response) {
            base = response.url ?? page
            html = String(decoding: data.prefix(1_000_000), as: UTF8.self)
        }
        for candidate in SiteIcon.candidates(html: html, base: base).prefix(5) {
            guard let (data, response) = try? await session.data(from: candidate.url), succeeded(response),
                  data.count < 2_000_000, isPicture(data) else { continue }
            return Icon(data: data, fillsTile: candidate.fillsTile)
        }
        return nil
    }

    private static func succeeded(_ response: URLResponse) -> Bool {
        (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }

    /// A picture at least 16 pixels wide, or a drawing: not an error page sent with a success.
    private static func isPicture(_ data: Data) -> Bool {
        guard let image = NSImage(data: data), image.size.width > 0 else { return false }
        let pixels = image.representations.map(\.pixelsWide)
        return pixels.contains(0) || (pixels.max() ?? 0) >= 16
    }
}
