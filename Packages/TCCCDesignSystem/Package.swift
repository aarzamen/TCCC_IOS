// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TCCCDesignSystem",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "TCCCDesignSystem", targets: ["TCCCDesignSystem"])],
    targets: [
        .target(name: "TCCCDesignSystem"),
        .testTarget(name: "TCCCDesignSystemTests", dependencies: ["TCCCDesignSystem"])
    ]
)
