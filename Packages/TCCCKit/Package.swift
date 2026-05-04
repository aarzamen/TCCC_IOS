// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TCCCKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "TCCCDomain", targets: ["TCCCDomain"]),
        .library(name: "TCCCExtractor", targets: ["TCCCExtractor"]),
        .library(name: "TCCCReports", targets: ["TCCCReports"]),
        .library(name: "TCCCDesign", targets: ["TCCCDesign"]),
    ],
    targets: [
        .target(
            name: "TCCCDomain",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TCCCExtractor",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TCCCReports",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TCCCDesign",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TCCCDomainTests",
            dependencies: ["TCCCDomain"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "TCCCExtractorTests",
            dependencies: ["TCCCExtractor"],
            resources: [
                .copy("Resources/scenarios"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
