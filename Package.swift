// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirplayifyJam",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AirplayifyJam", targets: ["AirplayifyJam"])
    ],
    targets: [
        .executableTarget(name: "AirplayifyJam"),
        .testTarget(name: "AirplayifyJamTests", dependencies: ["AirplayifyJam"])
    ]
)
