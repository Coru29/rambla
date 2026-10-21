// swift-tools-version: 6.0
import PackageDescription

// Only Command Line Tools are installed (no Xcode): Swift Testing lives outside the default search paths.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let cltDevLibs = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

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
            swiftSettings: [
                .unsafeFlags(["-F", cltFrameworks, "-plugin-path", cltTestingPlugins]),
            ],
            linkerSettings: [
                .unsafeFlags(["-F", cltFrameworks, "-framework", "Testing", "-Xlinker", "-rpath", "-Xlinker", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltDevLibs]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
