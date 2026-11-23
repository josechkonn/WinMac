// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WinMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WinMacCore", targets: ["WinMacCore"]),
        .executable(name: "WinMac", targets: ["WinMac"])
    ],
    targets: [
        .target(
            name: "WinMacCore",
            path: "Sources/WinMacCore"
        ),
        .executableTarget(
            name: "WinMac",
            dependencies: ["WinMacCore"],
            path: "Sources/WinMac"
        ),
        .testTarget(
            name: "WinMacCoreTests",
            dependencies: ["WinMacCore"],
            path: "Tests/WinMacCoreTests"
        )
    ]
)
