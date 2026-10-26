import AppKit

if let code = CLI.run(Array(CommandLine.arguments.dropFirst())) {
    exit(code)
}

// One Rambla at a time: a second one, started by hand (the binary run without an action, `open -n`), would manage the
// same windows as the one running. It leaves them to that one.
if CLI.anotherIsRunning {
    FileHandle.standardError.write(Data((String(localized: "Rambla ya está abierto.") + "\n").utf8))
    exit(1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
