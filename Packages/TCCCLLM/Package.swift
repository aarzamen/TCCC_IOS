// swift-tools-version: 6.1
//
// TCCCLLM — local shim package that brings AnyLanguageModel into the
// app target with the `MLX` package trait enabled. Xcode does not
// support declaring SPM package dependencies with traits directly
// (see AnyLanguageModel README §"Using Traits in Xcode Projects"),
// so we wrap it in a local Swift package whose `Package.swift` does
// the trait-enable here, and re-export the module via `@_exported`.
//
// Per the AnyLanguageModel README workaround for swift-package-manager
// issue #9286 ("exhausted attempts to resolve the dependencies graph"
// when traits are enabled), we also list the trait's underlying
// dependency (mlx-swift-lm) directly.
import PackageDescription

let package = Package(
    name: "TCCCLLM",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "TCCCLLM", targets: ["TCCCLLM"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/huggingface/AnyLanguageModel.git",
            from: "0.8.0",
            traits: ["MLX"]
        ),
        // Workaround for swift-package-manager#9286 — add the underlying
        // dep for every enabled trait so the resolver doesn't exhaust.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.25.5"),
    ],
    targets: [
        .target(
            name: "TCCCLLM",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ]
        ),
    ]
)
