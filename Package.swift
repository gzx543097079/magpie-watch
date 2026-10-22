// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MagpieWatch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MagpieWatch", targets: ["MagpieWatch"])
    ],
    targets: [
        .executableTarget(
            name: "MagpieWatch",
            path: "Sources/MagpieWatch"
        )
    ],
    swiftLanguageModes: [.v5]
)
