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
        "#!/bin/sh\nexec \(shellQuoted(executable)) \"$@\"\n"
    }

    /// `path` as one shell word, whatever it holds (a space, a quote, a `$`).
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
            ? "\(shellQuoted(executable)) \(action.rawValue)"
            : "open -g \"rambla://\(action.rawValue)\""
    }
}
