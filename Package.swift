// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ProDisplay",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ProDisplay",
            path: "Sources/ProDisplay",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
