import Testing
@testable import RamblaCore

private let temp = "/var/folders/ab/xyz/T/"

@Test func aLinkMayOnlyArrangeWindowsOrOpenTheSettings() {
    // Any web page can open a rambla:// link, so a link must not reach the diagnostics.
    for word in ["focus-left", "cycle-width", "toggle-pause", "settings", "gather", "relayout"] {
        #expect(CommandPolicy.allows(word, from: .url), "\(word)")
    }
    // Closing a window can lose work, so a web page must not be able to do it.
    for word in ["close-window", "dump", "debug-windows", "debug-update", "debug-external-move", "debug-neighbor", "nonsense"] {
        #expect(!CommandPolicy.allows(word, from: .url), "\(word)")
    }
}

@Test func linksMayChangeStrips() {
    // Changing strips, or sending a window to another one, only arranges windows: no more than a link may do.
    for word in ["strip-up", "strip-down", "send-strip-up", "send-strip-down"] {
        #expect(CommandPolicy.allows(word, from: .url), "\(word)")
        #expect(CommandPolicy.allows(word, from: .commandLine), "\(word)")
    }
}

@Test func theCommandLineMayAlsoAskForDiagnostics() {
    for word in ["focus-left", "close-window", "settings", "dump", "debug-windows", "debug-update", "debug-external-move",
                 "debug-neighbor"] {
        #expect(CommandPolicy.allows(word, from: .commandLine), "\(word)")
    }
    #expect(!CommandPolicy.allows("nonsense", from: .commandLine))
}

@Test func repliesGoOnlyToRamblasOwnFileInTheTemporaryFolder() {
    #expect(CommandPolicy.replyPath(temp + "rambla-reply-4242.json", temporaryDirectory: temp) == temp + "rambla-reply-4242.json")
    #expect(CommandPolicy.replyPath("/var/folders/ab/xyz/T/rambla-reply-1.json", temporaryDirectory: "/var/folders/ab/xyz/T")
            == "/var/folders/ab/xyz/T/rambla-reply-1.json")
    let refused = [
        "/Users/someone/.ssh/authorized_keys",                // anywhere else
        "/tmp/rambla-reply-4242.json",                        // another folder
        temp + "rambla-reply-.json",                          // no number
        temp + "rambla-reply-12a.json",                       // not only digits
        temp + "rambla-reply-12.json.bak",
        temp + "../rambla-reply-12.json",                     // out of the folder
        temp + "sub/rambla-reply-12.json",
        temp + "rambla-reply-١٢.json",                        // non-ASCII digits
        "",
    ]
    for path in refused {
        #expect(CommandPolicy.replyPath(path, temporaryDirectory: temp) == nil, "\(path)")
    }
}
