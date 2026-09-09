import XCTest
@testable import TCCC_IOS

final class OfflineModelAssetsTests: XCTestCase {
    private let modelID = "mlx-community/test-model"
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func write(_ name: String, _ text: String, at directory: URL? = nil) throws {
        try Data(text.utf8).write(to: (directory ?? root).appendingPathComponent(name))
    }

    private func completeMLX(at directory: URL? = nil) throws {
        let directory = directory ?? root!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("config.json", "{\"model_type\":\"fixture\"}", at: directory)
        try write("tokenizer_config.json", "{}", at: directory)
        try write("tokenizer.json", "{}", at: directory)
        let header = Data("{\"weight\":{\"dtype\":\"F32\",\"shape\":[1],\"data_offsets\":[0,4]}}".utf8)
        var length = UInt64(header.count).littleEndian
        var data = withUnsafeBytes(of: &length) { Data($0) }
        data.append(header)
        data.append(Data(repeating: 0, count: 4))
        try data.write(to: directory.appendingPathComponent("model.safetensors"))
    }

    func testMissingDirectoryIsNotReady() {
        XCTAssertNil(OfflineModelAssets.resolve(modelID: modelID, roots: [root], legacyCandidates: []))
    }

    func testEmptySnapshotIsNotReady() throws {
        let snapshot = root.appendingPathComponent("empty-revision")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        XCTAssertNil(OfflineModelAssets.resolve(modelID: modelID, roots: [], legacyCandidates: [snapshot]))
    }

    func testCompleteSnapshotResolvesLeaf() throws {
        let snapshot = root.appendingPathComponent("valid-revision")
        try completeMLX(at: snapshot)
        XCTAssertEqual(OfflineModelAssets.resolve(modelID: modelID, roots: [], legacyCandidates: [snapshot]), snapshot)
    }

    func testIndexAloneDoesNotCountAsWeights() throws {
        try completeMLX()
        try FileManager.default.removeItem(at: root.appendingPathComponent("model.safetensors"))
        try write("model.safetensors.index.json", "{\"weight_map\":{\"weight\":\"model-00001.safetensors\"}}")
        XCTAssertFalse(OfflineModelAssets.mlxProblems(at: root).isEmpty)
    }

    func testMissingIndexedShardIsNotReady() throws {
        try completeMLX()
        try write("model.safetensors.index.json", "{\"weight_map\":{\"a\":\"model.safetensors\",\"b\":\"missing.safetensors\"}}")
        XCTAssertFalse(OfflineModelAssets.mlxProblems(at: root).isEmpty)
    }

    func testTruncatedTensorPayloadIsNotReady() throws {
        try completeMLX()
        let path = root.appendingPathComponent("model.safetensors")
        var data = try Data(contentsOf: path)
        data.removeLast()
        try data.write(to: path)
        XCTAssertFalse(OfflineModelAssets.validSafetensors(path))
    }

    func testLFSPointerIsNotAWeight() throws {
        try completeMLX()
        try write("model.safetensors", "version https://git-lfs.github.com/spec/v1\noid sha256:000\nsize 123")
        XCTAssertFalse(OfflineModelAssets.mlxProblems(at: root).isEmpty)
    }

    func testInvalidFirstCandidateDoesNotHideValidLocalCopy() throws {
        let valid = root.appendingPathComponent("valid")
        try completeMLX(at: valid)
        XCTAssertEqual(OfflineModelAssets.resolve(modelID: modelID, roots: [root], legacyCandidates: [root, valid]), valid)
    }

    func testPackagedModelRequiresMatchingManifest() throws {
        let folder = root.appendingPathComponent("OfflineModels").appendingPathComponent(OfflineModelAssets.folderName(modelID))
        try completeMLX(at: folder)
        XCTAssertFalse(OfflineModelAssets.problems(at: folder, modelID: modelID).isEmpty)
        try write("asset-manifest.json", "{\"schemaVersion\":1,\"modelID\":\"wrong\",\"files\":[{\"path\":\"config.json\",\"bytes\":24}]}", at: folder)
        XCTAssertFalse(OfflineModelAssets.problems(at: folder, modelID: modelID).isEmpty)
    }

    func testUnsafeShardPathRejected() throws {
        try completeMLX()
        try write("model.safetensors.index.json", "{\"weight_map\":{\"a\":\"../model.safetensors\"}}")
        XCTAssertFalse(OfflineModelAssets.mlxProblems(at: root).isEmpty)
    }

    func testParakeetDirectoriesAloneAreNotReady() throws {
        try write("vocab.json", "{}")
        for name in ["streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        XCTAssertEqual(OfflineModelAssets.parakeetProblems(at: root).count, 3)
    }
    func testPackagedManifestDetectsMissingAndTruncatedFiles() throws {
        try completeMLX()
        let size = OfflineModelAssets.fileSize(root.appendingPathComponent("model.safetensors"))
        try write("asset-manifest.json", "{\"schemaVersion\":1,\"modelID\":\"\(modelID)\",\"files\":[{\"path\":\"model.safetensors\",\"bytes\":\(size)}]}")
        XCTAssertTrue(OfflineModelAssets.manifestProblems(at: root, modelID: modelID).isEmpty)
        try write("model.safetensors", "truncated")
        XCTAssertFalse(OfflineModelAssets.manifestProblems(at: root, modelID: modelID).isEmpty)
    }

    func testParakeetMissingWeightPayloadIsNotReady() throws {
        try write("vocab.json", "{}")
        for name in ["streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try write("coremldata.bin", "metadata", at: directory)
            try write("model.mil", "program", at: directory)
        }
        XCTAssertEqual(OfflineModelAssets.parakeetProblems(at: root).count, 3)
    }

    func testKokoroMissingLexiconAndVoicesIsNotReady() throws {
        try write("config.json", "{}")
        XCTAssertFalse(OfflineModelAssets.kokoroProblems(at: root).isEmpty)
    }

}
