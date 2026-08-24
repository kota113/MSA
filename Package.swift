// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacWSAHost",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacWSAHost", targets: ["MacWSAHost"])],
    targets: [
        .executableTarget(
            name: "MacWSAHost",
            path: "macos-host/Sources/MacWSAHost",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
            ]
        )
    ]
)
