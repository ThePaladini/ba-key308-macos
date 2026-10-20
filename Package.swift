// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BAKeyMenu",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BAKeyMenu", targets: ["BAKeyMenu"]),
        .executable(name: "bakey", targets: ["bakey"]),
        .library(name: "BAKeyCore", targets: ["BAKeyCore"]),
    ],
    targets: [
        // Protocol, HID transport and keyboard layout. No UI code.
        .target(
            name: "BAKeyCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // The menu bar app (SwiftUI).
        .executableTarget(
            name: "BAKeyMenu",
            dependencies: ["BAKeyCore"]
        ),
        // Command-line tool for scripting and protocol exploration.
        .executableTarget(
            name: "bakey",
            dependencies: ["BAKeyCore"]
        ),
        .testTarget(
            name: "BAKeyCoreTests",
            dependencies: ["BAKeyCore"]
        ),
    ]
)
