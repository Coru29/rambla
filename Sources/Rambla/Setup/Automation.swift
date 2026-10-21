import Foundation
import RamblaCore

/// The `rambla` terminal command and the Raycast scripts ("Configuración → Automatización").
/// The file contents live in `AutomationScripts` (RamblaCore); this file puts them on disk.
enum Automation {
    /// Installs `/usr/local/bin/rambla`. Returns an error message, or nil on success.
    ///
    /// If the folder is not writable for the user, asks for the administrator password with `osascript`. That call
    /// blocks until the password dialog is answered, so run it off the main thread if the UI must stay responsive.
    static func installCLI() -> String? {
        installCLI(at: AutomationScripts.cliInstallPath)
    }

    /// Writes one executable `rambla-<id>.sh` Raycast script command per action into `folder`, creating it if needed.
    /// Returns an error message, or nil on success.
    static func exportRaycast(to folder: URL) -> String? {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Log.error("Raycast export: cannot create \(folder.path): \(error.localizedDescription)")
            return "No se pudo crear la carpeta «\(folder.path)»: \(error.localizedDescription)"
        }
        for action in Action.allCases {
            let file = folder.appendingPathComponent(AutomationScripts.raycastFileName(for: action))
            do {
                try Data(AutomationScripts.raycastScript(for: action).utf8).write(to: file, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            } catch {
                Log.error("Raycast export: cannot write \(file.path): \(error.localizedDescription)")
                return "No se pudo escribir «\(file.lastPathComponent)» en «\(folder.path)»: \(error.localizedDescription)"
            }
        }
        Log.info("Exported \(Action.allCases.count) Raycast scripts to \(folder.path)")
        return nil
    }

    // MARK: Installing the command

    /// `installCLI()` with the destination as a parameter.
    static func installCLI(at path: String) -> String? {
        let script = AutomationScripts.cliScript
        let fileManager = FileManager.default
        // The write is atomic (temporary file, then rename), so an existing file or symlink at `path` is replaced
        // instead of written through, which matters if `rambla` was symlinked to the app binary by hand.
        do {
            try fileManager.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try script.write(toFile: path, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            Log.info("Installed the rambla command at \(path)")
            return nil
        } catch {
            Log.info("Cannot write \(path) as the current user (\(error.localizedDescription)); asking for administrator privileges")
        }
        return installWithAdministratorPrivileges(script: script, at: path)
    }

    /// Stages the script in a temporary file the user owns, then lets `install` copy it into place as root. Going through
    /// a file keeps the script text out of the shell and AppleScript quoting entirely; only paths are quoted.
    private static func installWithAdministratorPrivileges(script: String, at path: String) -> String? {
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("rambla-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staged) }
        do {
            try script.write(to: staged, atomically: false, encoding: .utf8)
        } catch {
            return "No se pudo preparar el comando: \(error.localizedDescription)"
        }
        let command = administratorInstallCommand(staged: staged.path, destination: path)
        let outcome = runProcess("/usr/bin/osascript", ["-e", administratorScript(running: command)])
        if outcome.status == 0 {
            Log.info("Installed the rambla command at \(path) with administrator privileges")
            return nil
        }
        // osascript reports a dismissed password dialog as "6:22: execution error: User canceled. (-128)".
        if outcome.errorText.contains("(-128)") { return "Se canceló la instalación del comando." }
        Log.error("Installing the rambla command failed: \(outcome.errorText)")
        return "No se pudo instalar el comando en \(path): \(reason(fromOsascript: outcome.errorText))"
    }

    /// The part of an osascript error that means something to the user: without the "0:51: execution error: " prefix.
    static func reason(fromOsascript errorText: String) -> String {
        let reason = errorText.replacingOccurrences(of: #"^\d+:\d+: execution error: "#, with: "", options: .regularExpression)
        return reason.isEmpty ? "error desconocido" : reason
    }

    /// Shell command run as root: make sure the folder exists (`mkdir -p` leaves an existing folder's permissions
    /// alone) and copy the staged file there as an executable. `install` replaces an existing file or symlink.
    static func administratorInstallCommand(staged: String, destination: String) -> String {
        let directory = (destination as NSString).deletingLastPathComponent
        return "/bin/mkdir -p \(shellQuoted(directory)) && /usr/bin/install -m 755 \(shellQuoted(staged)) \(shellQuoted(destination))"
    }

    /// AppleScript source that runs a shell command as administrator, which makes macOS ask for the password.
    static func administratorScript(running command: String) -> String {
        "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
    }

    /// Single-quotes text for `sh`; a single quote inside becomes `'\''`.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes text for a double-quoted AppleScript string literal.
    static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Runs a tool and waits for it. Only stderr is kept, and osascript writes just a line or two there, so reading
    /// it after the exit cannot fill the pipe. `waitUntilExit` keeps the run loop going while the password dialog is up.
    private static func runProcess(_ executable: String, _ arguments: [String]) -> (status: Int32, errorText: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        process.waitUntilExit()
        let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
