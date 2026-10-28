// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIPassportFlasher",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIPassportFlasher", targets: ["AIPassportFlasher"]),
    ],
    targets: [
        .executableTarget(
            name: "AIPassportFlasher",
            path: "Sources/AIPassportFlasher",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "AIPassportFlasherTests",
            dependencies: ["AIPassportFlasher"],
            path: "Tests/AIPassportFlasherTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
