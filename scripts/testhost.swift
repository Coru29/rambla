// A tiny regular app with plain resizable windows, so live tests never touch the user's real apps.
// Commands (distributed notification "TestHost.command"): "add", "quit".
import AppKit

final class Host: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let count = Int(CommandLine.arguments.dropFirst().first ?? "3") ?? 3
        for _ in 0..<count { add() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("TestHost.command"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                switch note.object as? String {
                case "add": self?.add()
                case "quit": NSApp.terminate(nil)
                default: break
                }
            }
        }
        NSApp.activate()
    }
    func add() {
        let n = windows.count + 1
        let w = NSWindow(contentRect: NSRect(x: 80 + n * 40, y: 120 + n * 30, width: 560, height: 420),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Prueba \(n)"
        w.isReleasedWhenClosed = false
        w.delegate = self
        let label = NSTextField(labelWithString: "Ventana de prueba \(n)")
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.frame = NSRect(x: 30, y: 180, width: 480, height: 40)
        w.contentView?.addSubview(label)
        w.makeKeyAndOrderFront(nil)
        windows.append(w)
    }
    func windowWillClose(_ notification: Notification) {
        // Drop the last reference so the window (and its WindowServer window) really goes away.
        if let w = notification.object as? NSWindow { DispatchQueue.main.async { self.windows.removeAll { $0 === w } } }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let host = Host()
    app.delegate = host
    app.setActivationPolicy(.regular)
    withExtendedLifetime(host) { app.run() }
}
