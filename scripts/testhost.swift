// A tiny regular app with plain resizable windows, so live tests never touch the user's real apps.
// Commands (distributed notification "TestHost.command"): "add", "quit", "hide", "unhide", "minimize N", "restore N"
// (N counts the windows in the order they were made, from 1), "label TEXT" (every window shows TEXT).
import AppKit

final class Host: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    var labels: [NSTextField] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let count = Int(CommandLine.arguments.dropFirst().first ?? "3") ?? 3
        for _ in 0..<count { add() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("TestHost.command"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                let words = (note.object as? String ?? "").split(separator: " ").map(String.init)
                let window = words.count > 1 ? Int(words[1]).flatMap { n in self?.windows.indices.contains(n - 1) == true ? self?.windows[n - 1] : nil } : nil
                switch words.first {
                case "add": self?.add()
                case "quit": NSApp.terminate(nil)
                case "hide": NSApp.hide(nil)
                case "unhide": NSApp.unhide(nil)
                case "minimize": window?.miniaturize(nil)
                case "restore": window?.deminiaturize(nil)
                case "label": self?.labels.forEach { $0.stringValue = words.dropFirst().joined(separator: " ") }
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
        labels.append(label)
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
