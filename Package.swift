// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chizu",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChizuCore", targets: ["ChizuCore"]),
        .executable(name: "chizu", targets: ["Chizu"]),
    ],
    targets: [
        .target(name: "ChizuCore"),
        .executableTarget(name: "Chizu", dependencies: ["ChizuCore"]),
        .testTarget(name: "ChizuCoreTests", dependencies: ["ChizuCore"]),
    ]
)
