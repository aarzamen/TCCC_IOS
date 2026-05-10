// swift-tools-version: 6.1
//
// TCCCAudio — local shim package that brings the heavy MLX-backed audio
// SDK into the app target without polluting Packages/TCCCKit (which is
// pure logic, no external SDK deps). Mirrors the existing
// Packages/TCCCLLM shim pattern.
//
// Sprint 1 scope (v3 spec, §G0): scaffold only. The real
// GraniteSpeechBookmarkStore / GraniteSpeechModelResolver /
// GraniteSpeechRuntime types land in §G1 and §G2.
//
// Why a separate package and not a TCCCKit submodule:
// mlx-audio-swift transitively pulls mlx-swift, mlx-swift-lm,
// swift-transformers, swift-huggingface — none of which belong in
// TCCCKit's pure-logic module set. Same isolation rationale as TCCCLLM.

import PackageDescription

let package = Package(
    name: "TCCCAudio",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "TCCCAudio", targets: ["TCCCAudio"]),
    ],
    dependencies: [
        // Pinned to the v0.1.2 tag's commit SHA per v3 §2 (decision row
        // "Speech runtime"). Resolved via:
        //   git ls-remote https://github.com/Blaizzy/mlx-audio-swift refs/tags/v0.1.2
        // Branch pinning is fragile; bump the SHA explicitly when moving
        // to a newer release.
        .package(
            url: "https://github.com/Blaizzy/mlx-audio-swift.git",
            revision: "fcbd04daa1bfebe881932f630af2ba6ce9af3274"
        ),
        // Transitive deps from mlx-audio-swift, declared explicitly so
        // TCCCAudio's own sources can `import` them. Versions match
        // mlx-audio-swift v0.1.2's lower bounds (per its Package.swift).
        // Used by GraniteSpeechModelLoader to load the model from a
        // user-picked URL directly (bypassing fromPretrained's
        // baked-in HF cache path mangling — see G2 commit message).
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.30.3"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.1.6"),
    ],
    targets: [
        .target(
            name: "TCCCAudio",
            dependencies: [
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Transformers", package: "swift-transformers"),
            ]
        ),
    ]
)
