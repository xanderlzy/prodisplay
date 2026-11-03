// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ProDisplay",
    platforms: [.macOS(.v14)],
    targets: [
        // Declarations for Apple's private CGVirtualDisplay classes (implemented in CoreGraphics).
        .target(name: "CGVirtualDisplayPrivate", path: "Sources/CGVirtualDisplayPrivate"),
        .executableTarget(
            name: "ProDisplay",
            dependencies: ["CGVirtualDisplayPrivate"],
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
