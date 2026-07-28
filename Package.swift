// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Presence",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Presence", targets: ["Presence"])
    ],
    targets: [
        .target(
            name: "PresenceCore"
        ),
        .executableTarget(
            name: "Presence",
            dependencies: ["PresenceCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "PresenceCoreTests",
            dependencies: ["PresenceCore"]
        )
    ]
)

