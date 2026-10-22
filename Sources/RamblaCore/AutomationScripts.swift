import Foundation

/// The text of the files Rambla installs or exports so other tools can drive it ("Configuración → Automatización").
public enum AutomationScripts {
    /// The binary inside the installed app. It runs `rambla <action>` itself when it receives an action argument.
    public static let appExecutable = "/Applications/Rambla.app/Contents/MacOS/Rambla"
    /// Where the `rambla` terminal command is installed.
    public static let cliInstallPath = "/usr/local/bin/rambla"

    /// The `rambla` command: hands every argument to the app binary.
    public static let cliScript = "#!/bin/sh\nexec \"\(appExecutable)\" \"$@\"\n"

    /// `rambla-<id>.sh`, the name of the Raycast script for an action.
    public static func raycastFileName(for action: Action) -> String {
        "rambla-\(action.rawValue).sh"
    }

    /// A Raycast script command that runs one action, and the `silent` mode makes Raycast close itself without showing
    /// any output.
    public static func raycastScript(for action: Action) -> String {
        """
        #!/bin/bash

        # Required parameters:
        # @raycast.schemaVersion 1
        # @raycast.title Rambla: \(action.title)
        # @raycast.mode silent

        # Optional parameters:
        # @raycast.packageName Rambla

        \(raycastCommand(for: action))

        """
    }

    /// Through the `rambla://` URL scheme, where `open -g` keeps whatever app is in front. An action links may not run
    /// (`CommandPolicy`) goes to the app binary, which runs it like the `rambla` command without that command installed.
    static func raycastCommand(for action: Action) -> String {
        CommandPolicy.commandLineOnly.contains(action)
            ? "\"\(appExecutable)\" \(action.rawValue)"
            : "open -g \"rambla://\(action.rawValue)\""
    }
}
