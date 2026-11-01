// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TripperDashCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "TripperDashCore", targets: ["TripperDashCore"])
    ],
    targets: [
        .target(name: "TripperDashCore"),
        .testTarget(name: "TripperDashCoreTests", dependencies: ["TripperDashCore"])
    ]
)
