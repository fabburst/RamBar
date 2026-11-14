// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RamBar",
    defaultLocalization: "fr",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "RamBarCore", targets: ["RamBarCore"]),
        .executable(name: "RamBar", targets: ["RamBar"])
    ],
    targets: [
        .target(
            name: "RamBarCore",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "RamBar",
            dependencies: ["RamBarCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "RamBarTests",
            dependencies: ["RamBarCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
