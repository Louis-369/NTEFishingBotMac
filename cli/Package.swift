// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacFishingBot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mac-fishing-bot", targets: ["MacFishingBot"])
    ],
    targets: [
        .executableTarget(
            name: "MacFishingBot",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
