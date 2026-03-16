// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftFlashCLI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftFlashCore",
            targets: ["SwiftFlashCore"]
        ),
        .executable(
            name: "swiftflash",
            targets: ["swiftflash"]
        )
    ],
    targets: [
        .target(
            name: "SwiftFlashCore"
        ),
        .executableTarget(
            name: "swiftflash",
            dependencies: ["SwiftFlashCore"]
        ),
        .testTarget(
            name: "SwiftFlashCoreTests",
            dependencies: ["SwiftFlashCore"]
        )
    ]
)
