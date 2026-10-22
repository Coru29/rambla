import Testing
import Foundation
@testable import RamblaCore

@Test func cliScriptHandsEveryArgumentToTheAppBinary() {
    #expect(AutomationScripts.cliInstallPath == "/usr/local/bin/rambla")
    #expect(AutomationScripts.defaultAppExecutable == "/Applications/Rambla.app/Contents/MacOS/Rambla")
    #expect(AutomationScripts.cliScript(executable: AutomationScripts.defaultAppExecutable)
        == "#!/bin/sh\nexec '/Applications/Rambla.app/Contents/MacOS/Rambla' \"$@\"\n")
}

@Test func theScriptsUseTheAppWhereverItIs() {
    // An app kept in ~/Applications, or in a folder whose name has a space or a quote.
    let odd = "/Users/me/My Apps/Ram'bla.app/Contents/MacOS/Rambla"
    let quoted = #"'/Users/me/My Apps/Ram'\''bla.app/Contents/MacOS/Rambla'"#
    #expect(AutomationScripts.cliScript(executable: odd) == "#!/bin/sh\nexec \(quoted) \"$@\"\n")
    #expect(AutomationScripts.raycastScript(for: .closeWindow, executable: odd).hasSuffix("\n\(quoted) close-window\n"))
    #expect(AutomationScripts.raycastScript(for: .focusLeft, executable: odd).hasSuffix("\nopen -g \"rambla://focus-left\"\n"))
}

@Test func raycastScriptMatchesTheRaycastTemplate() {
    let expected = """
    #!/bin/bash

    # Required parameters:
    # @raycast.schemaVersion 1
    # @raycast.title Rambla: Enfocar columna izquierda
    # @raycast.mode silent

    # Optional parameters:
    # @raycast.packageName Rambla

    open -g "rambla://focus-left"

    """
    #expect(AutomationScripts.raycastScript(for: .focusLeft) == expected)
    #expect(AutomationScripts.raycastFileName(for: .focusLeft) == "rambla-focus-left.sh")
}

@Test func raycastScriptsExistForEveryActionWithTheirOwnHeaderAndURL() {
    var fileNames: Set<String> = []
    for action in Action.allCases {
        let name = AutomationScripts.raycastFileName(for: action)
        #expect(name == "rambla-\(action.rawValue).sh")
        fileNames.insert(name)

        let script = AutomationScripts.raycastScript(for: action)
        let lines = script.components(separatedBy: "\n")
        #expect(lines.first == "#!/bin/bash", "\(action.rawValue)")
        #expect(lines.contains("# @raycast.schemaVersion 1"), "\(action.rawValue)")
        #expect(lines.contains("# @raycast.title Rambla: \(action.title)"), "\(action.rawValue)")
        #expect(lines.contains("# @raycast.mode silent"), "\(action.rawValue)")
        #expect(lines.contains("# @raycast.packageName Rambla"), "\(action.rawValue)")
        #expect(lines.filter { $0.hasPrefix("# @raycast.title") }.count == 1, "a title must fit on one line: \(action.rawValue)")
        // Every script runs its action the way the app accepts it: a link, or the app binary for what links may not run.
        if script.hasSuffix("open -g \"rambla://\(action.rawValue)\"\n") {
            #expect(CommandPolicy.allows(action.rawValue, from: .url), "a link cannot run \(action.rawValue)")
        } else {
            #expect(script.hasSuffix("\n'\(AutomationScripts.defaultAppExecutable)' \(action.rawValue)\n"), "\(action.rawValue)")
            #expect(CommandPolicy.allows(action.rawValue, from: .commandLine), "\(action.rawValue)")
        }
        // The id must round-trip through the URL scheme the app handles.
        #expect(URL(string: "rambla://\(action.rawValue)")?.host == action.rawValue, "\(action.rawValue)")
    }
    #expect(fileNames.count == Action.allCases.count, "file names must be unique")
}

@Test func closeWindowRunsThroughTheAppBinaryBecauseLinksCannotCloseWindows() {
    #expect(AutomationScripts.raycastScript(for: .closeWindow)
        .hasSuffix("\n'/Applications/Rambla.app/Contents/MacOS/Rambla' close-window\n"))
}
