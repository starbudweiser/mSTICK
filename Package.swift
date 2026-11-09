// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mSTICK",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "mSTICKCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "mSTICK", dependencies: ["mSTICKCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "mSTICKTests", dependencies: ["mSTICKCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
