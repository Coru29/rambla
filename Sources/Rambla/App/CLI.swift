import AppKit

/// Command-line mode of the app binary: `Rambla <action>` forwards the action to the running app.
enum CLI {
    static let bundleID = "io.github.coru29.Rambla"
    static let commandNotification = Notification.Name("io.github.coru29.Rambla.command")
    /// Commands that print a JSON reply written by the running app to a temporary file.
    static let replyCommands: Set<String> = ["dump", "debug-windows"]

    /// Returns an exit code when the arguments are a CLI invocation, or nil to launch the app.
    static func run(_ args: [String]) -> Int32? {
        guard let first = args.first else { return nil }
        if first == "list" || first == "help" || first == "--help" || first == "-h" {
            print(usage)
            return 0
        }
        guard !first.hasPrefix("-") else { return nil }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            FileHandle.standardError.write(Data("Rambla no está abierto.\n".utf8))
            return 1
        }
        if replyCommands.contains(first) {
            return request(first)
        }
        post(args.joined(separator: " "))
        return 0
    }

    private static func post(_ command: String) {
        DistributedNotificationCenter.default().postNotificationName(
            commandNotification, object: command, userInfo: nil, deliverImmediately: true)
    }

    /// Posts "<command> <reply-path>" and prints the file the app writes there.
    private static func request(_ command: String) -> Int32 {
        let path = NSTemporaryDirectory() + "rambla-reply-\(getpid()).json"
        try? FileManager.default.removeItem(atPath: path)
        post("\(command) \(path)")
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
        FileHandle.standardError.write(Data("Rambla no respondió.\n".utf8))
        return 1
    }

    static var usage: String {
        """
        Uso: rambla <acción>
        Ejemplos: rambla focus-left · rambla cycle-width · rambla focus-3 · rambla toggle-pause
        También por URL: open -g "rambla://focus-left"
        """
    }
}
