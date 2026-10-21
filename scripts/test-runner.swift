// Runs Swift Testing tests without Xcode: `swift test` skips Swift Testing when only Command Line Tools are installed.
// Loads the test bundle named by RAMBLA_TEST_BUNDLE and hands the remaining arguments (e.g. --filter) to Swift Testing.
import Testing
import Foundation

guard let bundle = ProcessInfo.processInfo.environment["RAMBLA_TEST_BUNDLE"] else {
    FileHandle.standardError.write("RAMBLA_TEST_BUNDLE not set\n".data(using: .utf8)!)
    exit(2)
}
guard dlopen(bundle, RTLD_NOW) != nil else {
    FileHandle.standardError.write("cannot load \(bundle): \(String(cString: dlerror()))\n".data(using: .utf8)!)
    exit(2)
}
let code: Int32 = await Testing.__swiftPMEntryPoint(passing: nil)
exit(code)
