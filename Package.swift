// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MiniBrowser",
    platforms: [
        .macOS(.v26)   // fallback if rejected by toolchain: .macOS("26.0")
    ],
    products: [
        .library(name: "MiniBrowserCore", targets: ["MiniBrowserCore"])
    ],
    dependencies: [],
    targets: [
        .target(name: "MiniBrowserCore"),
        .executableTarget(
            name: "MiniBrowserApp",
            dependencies: [.target(name: "MiniBrowserCore")]
        ),
        .testTarget(
            name: "MiniBrowserCoreTests",
            dependencies: [.target(name: "MiniBrowserCore")]
        )
    ]
)
