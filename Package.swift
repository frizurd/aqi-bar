// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AQIBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AQIBar", targets: ["AQIBar"])],
    targets: [
        .target(name: "AQICore"),
        .executableTarget(name: "AQIBar", dependencies: ["AQICore"]),
        .testTarget(name: "AQICoreTests", dependencies: ["AQICore"])
    ]
)
