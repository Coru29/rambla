import Foundation

/// What the text commands may do depending on where they come from.
///
/// Any web page can open a `rambla://` link (after one click on the browser's prompt), so a link is trusted with no
/// more than arranging windows. The command line is the `rambla` command, whose commands only the user's own programs
/// can leave for the app (any app, even a sandboxed one, can post the notification that wakes it, and that alone counts
/// as a link). It also gets the diagnostics, but their replies are written only to Rambla's own reply file in the
/// user's temporary folder, never to a path chosen by whoever sent the command.
public enum CommandPolicy {
    public enum Source: Sendable { case url, commandLine }

    /// Words that are not actions.
    static let windowCommands: Set<String> = ["settings", "gather", "relayout"]
    static let diagnostics: Set<String> = ["dump", "debug-windows", "debug-update", "debug-external-move", "debug-neighbor",
                                           "debug-logout", "debug-unseen-move"]

    /// Actions a link may not run: closing a window can lose work.
    static let commandLineOnly: Set<Action> = [.closeWindow]

    public static func allows(_ word: String, from source: Source) -> Bool {
        if let action = Action.parse(word) { return source == .commandLine || !commandLineOnly.contains(action) }
        if windowCommands.contains(word) { return true }
        return source == .commandLine && diagnostics.contains(word)
    }

    static let replyPrefix = "rambla-reply-"
    static let replySuffix = ".json"

    /// `requested` when it is `<temporaryDirectory>/rambla-reply-<digits>.json`, the file the `rambla` command reads
    /// the reply from; nil for any other path.
    public static func replyPath(_ requested: String, temporaryDirectory: String) -> String? {
        let folder = (temporaryDirectory as NSString).standardizingPath
        let path = (requested as NSString).standardizingPath
        guard !requested.isEmpty, (path as NSString).deletingLastPathComponent == folder else { return nil }
        let name = (path as NSString).lastPathComponent
        guard name.hasPrefix(replyPrefix), name.hasSuffix(replySuffix) else { return nil }
        let digits = name.dropFirst(replyPrefix.count).dropLast(replySuffix.count)
        guard !digits.isEmpty, digits.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return path
    }
}
