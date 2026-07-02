// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TCCCKit",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "TCCCDomain", targets: ["TCCCDomain"]),
        .library(name: "TCCCExtractor", targets: ["TCCCExtractor"]),
        .library(name: "TCCCReports", targets: ["TCCCReports"]),
        .library(name: "TCCCDesign", targets: ["TCCCDesign"]),
        .library(name: "TCCCBench", targets: ["TCCCBench"]),
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
            dependencies: ["TCCCDomain"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TCCCReports",
            dependencies: ["TCCCDomain"],
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
        .target(
            name: "TCCCBench",
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
            dependencies: ["TCCCExtractor", "TCCCDomain"],
            resources: [
                .copy("Resources/scenarios"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "TCCCReportsTests",
            dependencies: ["TCCCReports", "TCCCDomain"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "TCCCBenchTests",
            dependencies: ["TCCCBench"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
