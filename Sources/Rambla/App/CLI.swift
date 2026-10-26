import AppKit
import RamblaCore

/// Command-line mode of the app binary: `Rambla <action>` forwards the action to the running app.
enum CLI {
    static let bundleID = "io.github.coru29.Rambla"
    static let commandNotification = Notification.Name("io.github.coru29.Rambla.command")
    /// Commands that print a JSON reply written by the running app to a temporary file.
    static let replyCommands: Set<String> = ["dump", "debug-windows"]

    /// Returns an exit code when the arguments are a CLI invocation, or nil to launch the app.
    static func run(_ args: [String]) -> Int32? {
        guard let first = args.first else { return nil }
        if first == "list" {
            // Every action id the app understands, with its name. Links run all of them but close-window.
            let width = Action.allCases.map(\.rawValue.count).max() ?? 0
            for action in Action.allCases {
                print(action.rawValue.padding(toLength: width + 2, withPad: " ", startingAt: 0) + action.title)
            }
            return 0
        }
        if first == "help" || first == "--help" || first == "-h" {
            print(usage)
            return 0
        }
        guard !first.hasPrefix("-") else { return nil }
        guard CommandPolicy.allows(first, from: .commandLine) else {
            FileHandle.standardError.write(Data((String(localized: "«\(first)» no es una acción de Rambla: rambla list muestra todas.") + "\n").utf8))
            return 1
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            FileHandle.standardError.write(Data((String(localized: "Rambla no está abierto.") + "\n").utf8))
            return 1
        }
        if replyCommands.contains(first) {
            return request(first)
        }
        // Without the inbox only what a link may do goes through (`post`): closing a window does not.
        guard post(args.joined(separator: " ")) || CommandPolicy.allows(first, from: .url) else { return failed() }
        return 0
    }

    /// Another Rambla is running: one started now would manage the same windows.
    static var anotherIsRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != getpid() && !$0.isTerminated }
    }

    private static func failed() -> Int32 {
        FileHandle.standardError.write(Data((String(localized: "No se pudo pasar la orden a Rambla.") + "\n").utf8))
        return 1
    }

    /// Where the `rambla` command leaves its commands for the running app: a folder only the user's own programs can
    /// write to. The notification only says to look there, so an app that can post it but not write there (a
    /// sandboxed one) gets no more than a link (`CommandPolicy`).
    static var inbox: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Rambla/Commands", isDirectory: true)
    }

    /// Leaves `command` in the inbox and wakes the app; returns false when the inbox could not be written, and then
    /// the command still goes, trusted like a link.
    @discardableResult
    private static func post(_ command: String) -> Bool {
        let file = inbox.appendingPathComponent(String(format: "%.6f-%d.command", Date().timeIntervalSince1970, getpid()))
        let left: Bool
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try Data(command.utf8).write(to: file, options: .atomic)
            left = true
        } catch {
            left = false
        }
        DistributedNotificationCenter.default().postNotificationName(
            commandNotification, object: left ? nil : command, userInfo: nil, deliverImmediately: true)
        return left
    }

    /// The commands the `rambla` command left since the last call, oldest first. One older than a few seconds, left
    /// when Rambla was not there to take it, is dropped.
    static func takeCommands(now: Date = Date()) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var commands: [(date: Date, text: String)] = []
        for file in files where file.pathExtension == "command" {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(date) < 5, let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            commands.append((date, text))
        }
        return commands.sorted { $0.date < $1.date }.map(\.text)
    }

    /// Posts "<command> <reply-path>" and prints the file the app writes there.
    private static func request(_ command: String) -> Int32 {
        let path = NSTemporaryDirectory() + "rambla-reply-\(getpid()).json"
        try? FileManager.default.removeItem(atPath: path)
        guard post("\(command) \(path)") else { return failed() }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let data = FileManager.default.contents(atPath: path), !data.isEmpty {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                try? FileManager.default.removeItem(atPath: path)
                return 0
            }
            usleep(30_000)
        }
        FileHandle.standardError.write(Data((String(localized: "Rambla no respondió.") + "\n").utf8))
        return 1
    }

    static var usage: String {
        String(localized: """
        Uso: rambla <acción>
        Ejemplos: rambla focus-left · rambla cycle-width · rambla focus-3 · rambla toggle-pause
        rambla list muestra todas las acciones.
        También por URL: open -g "rambla://focus-left"
        """)
    }
}
