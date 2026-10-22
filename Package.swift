// swift-tools-version: 6.0
import Foundation
import PackageDescription

// With only the Command Line Tools (no Xcode), Swift Testing lives outside the default search paths. A build that
// picks Xcode through DEVELOPER_DIR (CI does) finds it by itself and must not mix in the tools' copy.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let cltDevLibs = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let usesXcode = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]?.contains(".app/") == true
let testingSwiftFlags: [SwiftSetting] = usesXcode ? [] : [.unsafeFlags(["-F", cltFrameworks, "-plugin-path", cltTestingPlugins])]
let testingLinkerFlags: [LinkerSetting] = usesXcode ? [] : [
    .unsafeFlags(["-F", cltFrameworks, "-framework", "Testing", "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                  "-Xlinker", "-rpath", "-Xlinker", cltDevLibs]),
]

let package = Package(
    name: "Rambla",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Rambla", targets: ["Rambla"]),
    ],
    targets: [
        .target(
            name: "RamblaCore",
            path: "Sources/RamblaCore"
        ),
        .executableTarget(
            name: "Rambla",
            dependencies: ["RamblaCore"],
            path: "Sources/Rambla",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "RamblaCoreTests",
            dependencies: ["RamblaCore"],
            path: "Tests/RamblaCoreTests",
            swiftSettings: testingSwiftFlags,
            linkerSettings: testingLinkerFlags
        ),
    ],
    swiftLanguageModes: [.v5]
)
