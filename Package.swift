// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ProDisplay",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Self-updates. Pinned exactly; update deliberately.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "ProDisplay",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ProDisplay",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                // build.sh embeds Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
