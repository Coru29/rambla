import Foundation
import Testing
@testable import RamblaCore

// A browser window shows the icon of the site it is on: where the site keeps it, best first.

private let youtube = URL(string: "https://www.youtube.com/")!

@Test func theLargestIconOfThePageComesFirst() {
    let html = """
        <html><head>
        <link rel="shortcut icon" href="https://www.youtube.com/s/img/favicon.ico" type="image/x-icon">
        <link rel="icon" href="https://www.youtube.com/s/img/favicon_32x32.png" sizes="32x32">
        <link rel="icon" href="https://www.youtube.com/s/img/favicon_144x144.png" sizes="144x144">
        <link rel="icon" href="https://www.youtube.com/s/img/favicon_96x96.png" sizes="96x96">
        </head><body></body></html>
        """
    let found = SiteIcon.candidates(html: html, base: youtube)
    // A touch icon may be at its usual place: bigger, it is tried first.
    #expect(found.map(\.url.path) == ["/apple-touch-icon.png", "/s/img/favicon_144x144.png", "/s/img/favicon_96x96.png",
                                      "/s/img/favicon.ico", "/s/img/favicon_32x32.png", "/favicon.ico"])
    #expect(found[1] == SiteIcon.Candidate(url: URL(string: "https://www.youtube.com/s/img/favicon_144x144.png")!,
                                           size: 144, fillsTile: false))
}

@Test func aDrawingComesBeforeAnyPictureAndAMaskIconIsNotOne() {
    let html = """
        <link rel="mask-icon" href="https://github.githubassets.com/pinned-octocat.svg" color="#000000">
        <link rel="fluid-icon" href="https://github.com/fluidicon.png" title="GitHub">
        <link rel="alternate icon" type="image/png" href="https://github.githubassets.com/favicons/favicon.png">
        <link rel="icon" type="image/svg+xml" href="https://github.githubassets.com/favicons/favicon.svg">
        """
    let found = SiteIcon.candidates(html: html, base: URL(string: "https://github.com/")!)
    #expect(found.first?.url.lastPathComponent == "favicon.svg")
    #expect(found.first?.size == SiteIcon.scalable)
    // GitHub's large icon fills a tile, as a touch icon does.
    #expect(found.dropFirst().first == SiteIcon.Candidate(url: URL(string: "https://github.com/fluidicon.png")!,
                                                          size: 512, fillsTile: true))
    #expect(!found.contains { $0.url.lastPathComponent == "pinned-octocat.svg" })
}

@Test func relativeAndSchemeRelativeAddressesComeFromThePage() {
    let html = """
        <link rel="icon" type="image/png" href="assets/favicon.png">
        <link rel="apple-touch-icon" href="assets/apple-touch-icon.png">
        <link href='//www.gstatic.com/images/branding/favicon.ico' rel='icon'>
        """
    let found = SiteIcon.candidates(html: html, base: URL(string: "https://rambla-mac.app/")!)
    #expect(found.first == SiteIcon.Candidate(url: URL(string: "https://rambla-mac.app/assets/apple-touch-icon.png")!,
                                              size: 180, fillsTile: true))
    #expect(found.contains { $0.url.absoluteString == "https://rambla-mac.app/assets/favicon.png" })
    #expect(found.contains { $0.url.absoluteString == "https://www.gstatic.com/images/branding/favicon.ico" })
}

@Test func withNoIconOnThePageTheUsualPlacesAreTried() {
    let found = SiteIcon.candidates(html: "<html><head><title>Cloudflare</title></head></html>",
                                    base: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!)
    #expect(found == [
        SiteIcon.Candidate(url: URL(string: "https://dash.cloudflare.com/apple-touch-icon.png")!, size: 180,
                           fillsTile: true),
        SiteIcon.Candidate(url: URL(string: "https://dash.cloudflare.com/favicon.ico")!, size: 32, fillsTile: false),
    ])
}

@Test func theUsualPlacesComeOnceAmongThePagesIconsBySize() {
    let html = #"<link rel="icon" href="/favicon.ico"><link rel="icon" href="/logo.png" sizes="16x16 64x64">"#
    let found = SiteIcon.candidates(html: html, base: youtube)
    #expect(found.map(\.url.path) == ["/apple-touch-icon.png", "/logo.png", "/favicon.ico"])
    #expect(found.map(\.size) == [180, 64, 32])
}

@Test func onlyTheHeadOfThePageCounts() {
    let html = #"<head></head><body><link rel="icon" href="/late.png" sizes="512x512"></body>"#
    #expect(!SiteIcon.candidates(html: html, base: youtube).contains { $0.url.path == "/late.png" })
}

@Test func onlyWebPagesHaveASite() {
    #expect(SiteIcon.host(of: URL(string: "https://WWW.YouTube.com/watch?v=1")!) == "www.youtube.com")
    #expect(SiteIcon.host(of: URL(string: "http://localhost:3000/")!) == "localhost")
    #expect(SiteIcon.host(of: URL(string: "favorites://")!) == nil)
    #expect(SiteIcon.host(of: URL(string: "file:///Users/me/page.html")!) == nil)
    #expect(SiteIcon.siteName(ofHost: "www.youtube.com") == "youtube.com")
    #expect(SiteIcon.siteName(ofHost: "dash.cloudflare.com") == "dash.cloudflare.com")
}
