import AppKit

if let code = CLI.run(Array(CommandLine.arguments.dropFirst())) {
    exit(code)
}

// One Rambla at a time: a second one, started by hand (the binary run without an action, `open -n`), would manage the
// same windows as the one running. It leaves them to a Rambla that started before it, once it has waited a moment for
// that one to go in case it is quitting (quit and opened again right away). One started after it yields to it in
// turn, so two started at once leave exactly one. Started from Finder or the Dock nobody sees the message: the log
// says it too.
let older = CLI.olderInstances()
if !older.isEmpty, !CLI.waitForExit(of: older, timeout: 2) {
    FileHandle.standardError.write(Data((String(localized: "Rambla ya está abierto.") + "\n").utf8))
    let pids = older.map { "\($0)" }.joined(separator: ", ")
    Log.info("A Rambla that started before this one is running (pid \(pids)): this one quits")
    Log.flush()
    exit(1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
