// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AIUsageCore", targets: ["AIUsageCore"]),
        .executable(name: "AIUsage", targets: ["AIUsageApp"]),
    ],
    targets: [
        .target(name: "AIUsageCore"),
        .executableTarget(name: "AIUsageApp", dependencies: ["AIUsageCore"]),
        .testTarget(name: "AIUsageCoreTests", dependencies: ["AIUsageCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
