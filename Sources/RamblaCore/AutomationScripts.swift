import Foundation

/// The text of the files Rambla installs or exports so other tools can drive it ("Configuración → Automatización").
public enum AutomationScripts {
    /// The binary of an app installed in Applications. It runs `rambla <action>` itself when it receives an action
    /// argument. The scripts use the binary of the running app, wherever it is; this is for when it cannot tell.
    public static let defaultAppExecutable = "/Applications/Rambla.app/Contents/MacOS/Rambla"
    /// Where the `rambla` terminal command is installed.
    public static let cliInstallPath = "/usr/local/bin/rambla"

    /// The `rambla` command: hands every argument to the app binary at `executable`.
    public static func cliScript(executable: String) -> String {
        "#!/bin/sh\n" + appCommand(executable: executable, arguments: "\"$@\"", replacingShell: true) + "\n"
    }

    /// Runs the app binary at `executable` with `arguments`, or the one in Applications when the app has moved there
    /// since the script was written (from Downloads, say).
    static func appCommand(executable: String, arguments: String, replacingShell: Bool = false) -> String {
        let run = replacingShell ? "exec " : ""
        guard executable != defaultAppExecutable else { return "\(run)\(shellQuoted(executable)) \(arguments)" }
        return "app=\(shellQuoted(executable))\n[ -x \"$app\" ] || app=\(shellQuoted(defaultAppExecutable))\n\(run)\"$app\" \(arguments)"
    }

    /// `text` as one shell word, whatever it holds (a space, a quote, a `$`).
    public static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `rambla-<id>.sh`, the name of the Raycast script for an action.
    public static func raycastFileName(for action: Action) -> String {
        "rambla-\(action.rawValue).sh"
    }

    /// A Raycast script command that runs one action, and the `silent` mode makes Raycast close itself without showing
    /// any output.
    public static func raycastScript(for action: Action, executable: String = defaultAppExecutable) -> String {
        """
        #!/bin/bash

        # Required parameters:
        # @raycast.schemaVersion 1
        # @raycast.title Rambla: \(action.title)
        # @raycast.mode silent

        # Optional parameters:
        # @raycast.packageName Rambla

        \(raycastCommand(for: action, executable: executable))

        """
    }

    /// Through the `rambla://` URL scheme, where `open -g` keeps whatever app is in front. An action links may not run
    /// (`CommandPolicy`) goes to the app binary, which runs it like the `rambla` command without that command installed.
    static func raycastCommand(for action: Action, executable: String) -> String {
        CommandPolicy.commandLineOnly.contains(action)
            ? appCommand(executable: executable, arguments: action.rawValue)
            : "open -g \"rambla://\(action.rawValue)\""
    }
}
