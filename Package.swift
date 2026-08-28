// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MSAHost",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MSAAppHost", targets: ["MSAAppHost"]),
        .executable(name: "MSAEmulatorManager", targets: ["MSAEmulatorManager"]),
    ],
    targets: [
        .target(
            name: "MSAHostCore",
            path: "macos-host/Sources/MSAHostCore"
        ),
        .executableTarget(
            name: "MSAAppHost",
            dependencies: ["MSAHostCore"],
            path: "macos-host/Sources/MSAAppHost",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
            ]
        ),
        .executableTarget(
            name: "MSAEmulatorManager",
            dependencies: ["MSAHostCore"],
            path: "macos-host/Sources/MSAEmulatorManager",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreLocation"),
            ]
        ),
        .testTarget(
            name: "MSAHostTests",
            dependencies: ["MSAHostCore", "MSAAppHost", "MSAEmulatorManager"],
            path: "macos-host/Tests/MSAHostTests"
        ),
    ]
)
