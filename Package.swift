// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Atmora",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Atmora", targets: ["Atmora"])
    ],
    targets: [
        .target(
            name: "AtmoraCore"
        ),
        .executableTarget(
            name: "Atmora",
            dependencies: ["AtmoraCore"]
        ),
        .testTarget(
            name: "AtmoraCoreTests",
            dependencies: ["AtmoraCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
