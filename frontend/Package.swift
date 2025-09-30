// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PushToType",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "PushToType",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
