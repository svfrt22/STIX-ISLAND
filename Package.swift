// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "STIXIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "STIXIsland",
            path: "Sources/STIXIsland",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
