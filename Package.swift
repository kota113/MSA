// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MSAHost",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MSAHost", targets: ["MSAHost"])],
    targets: [
        .executableTarget(
            name: "MSAHost",
            path: "macos-host/Sources/MSAHost",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
            ]
        ),
        .testTarget(
            name: "MSAHostTests",
            dependencies: ["MSAHost"],
            path: "macos-host/Tests/MSAHostTests"
        ),
    ]
)
