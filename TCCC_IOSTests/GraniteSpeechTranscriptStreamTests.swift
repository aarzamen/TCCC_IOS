import XCTest
@testable import TCCC_IOS
import TCCCAudio

/// Sprint 1 (Granite Speech Foundation v3 §G1) policy tests.
///
/// These replace the prior placeholder assertions ("Swift runtime does
/// not exist" — false history per v3 §9). The new tests exercise the
/// resolver chain, bookmark store roundtrip, default-ASR-stays-Apple
/// regression, and the env-gated physical-device prime path.
@MainActor
final class GraniteSpeechTranscriptStreamTests: XCTestCase {

    // MARK: Policy: explicit alternate, never default

    func testGraniteSpeechIsExplicitAlternateASRBackend() {
        XCTAssertEqual(AppState().asrBackend, .appleSpeech)
        XCTAssertTrue(AppState.ASRBackend.allCases.contains(.graniteSpeech))
        XCTAssertNotEqual(AppState.ASRBackend.allCases.first, .graniteSpeech)
        XCTAssertEqual(
            AppState.ASRBackend.graniteSpeech.displayName,
            "Granite Speech (alt)"
        )
    }

    // MARK: Policy: resolver throws when no source has anything

    func testGraniteSpeechResolverThrowsWithoutAnySource() async {
        // Fresh bookmark store under a unique key — guaranteed empty.
        let isolatedKey = "test.granite.bookmark.\(UUID().uuidString)"
        let store = GraniteSpeechBookmarkStore(key: isolatedKey)
        defer { store.clear() }

        let resolver = GraniteSpeechModelResolver(
            bookmarkStore: store,
            bundleResourceCheck: { nil },
            hfCacheLookup: { _ in nil }
        )

        do {
            _ = try await resolver.resolve()
            XCTFail("Resolver should have thrown when no source resolves.")
        } catch GraniteSpeechResolverError.modelNotProvided(let id) {
            XCTAssertEqual(id, GraniteSpeechModelResolver.defaultModelID)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: Policy: bookmark roundtrip in UserDefaults

    func testBookmarkSaveResolveStaleClearLifecycle() throws {
        let isolatedKey = "test.granite.bookmark.\(UUID().uuidString)"
        let store = GraniteSpeechBookmarkStore(key: isolatedKey)
        defer { store.clear() }

        // Use a real in-sandbox directory. Bookmarks of in-sandbox URLs
        // don't carry security-scope semantics but the persistence +
        // resolve round-trip is the same code path.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("granite-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmpDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        XCTAssertFalse(store.hasBookmark)

        try store.save(url: tmpDir)
        XCTAssertTrue(store.hasBookmark)

        let (resolved, isStale) = try store.resolve()
        XCTAssertEqual(
            resolved.standardizedFileURL.lastPathComponent,
            tmpDir.standardizedFileURL.lastPathComponent
        )
        XCTAssertFalse(isStale)

        store.clear()
        XCTAssertFalse(store.hasBookmark)

        do {
            _ = try store.resolve()
            XCTFail("resolve() should throw after clear()")
        } catch GraniteSpeechBookmarkError.noBookmarkSaved {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: Policy: TranscriptStream surfaces backendUnavailable when no source

    func testGraniteSpeechTranscriptStreamAuthorizeThrowsBackendUnavailableWithoutSource() async {
        let isolatedKey = "test.granite.bookmark.\(UUID().uuidString)"
        let store = GraniteSpeechBookmarkStore(key: isolatedKey)
        defer { store.clear() }

        let resolver = GraniteSpeechModelResolver(
            bookmarkStore: store,
            bundleResourceCheck: { nil },
            hfCacheLookup: { _ in nil }
        )
        let runtime = GraniteSpeechRuntime(resolver: resolver)
        let stream = GraniteSpeechTranscriptStream(runtime: runtime)

        do {
            try await stream.authorize()
            XCTFail("authorize() should throw when no resolver source has the model.")
        } catch TranscriptStreamError.backendUnavailable(let message) {
            XCTAssertTrue(
                message.contains("Granite Speech"),
                "Expected error message to name Granite Speech, got: \(message)"
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGraniteSpeechStartAlwaysThrowsInG1() async {
        // start(audioURL:) is unimplemented in Sprint 1 G1 by design;
        // G2 wires the actual MLX model. The throw guards against any
        // accidental UI path that calls start before G2 lands.
        let stream = GraniteSpeechTranscriptStream()
        do {
            _ = try await stream.start(audioURL: nil)
            XCTFail("start(audioURL:) should throw in Sprint 1 G1.")
        } catch TranscriptStreamError.backendUnavailable(let message) {
            XCTAssertTrue(
                message.contains("not implemented"),
                "Expected message to flag the unimplemented state, got: \(message)"
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: Env-gated: real prime() path with a configured folder

    /// Set `GRANITE_SPEECH_MODEL_DIR` in the test scheme's environment
    /// to the path of an existing directory (any directory works for
    /// this G1 test — G2 verifies the actual `fromPretrained` load).
    /// Skipped otherwise so CI / local runs without the env var stay
    /// green.
    func testGraniteSpeechPrimeWithConfiguredFolderOnSimulator() async throws {
        guard let raw = ProcessInfo.processInfo
                .environment["GRANITE_SPEECH_MODEL_DIR"],
              !raw.isEmpty else {
            throw XCTSkip("Set GRANITE_SPEECH_MODEL_DIR to run.")
        }
        let modelURL = URL(fileURLWithPath: raw, isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: modelURL.path),
            "GRANITE_SPEECH_MODEL_DIR points at a path that does not exist: \(raw)"
        )

        let resolver = GraniteSpeechModelResolver(
            bookmarkStore: GraniteSpeechBookmarkStore(
                key: "test.granite.prime.\(UUID().uuidString)"
            ),
            bundleResourceCheck: { modelURL },
            hfCacheLookup: { _ in nil }
        )
        let runtime = GraniteSpeechRuntime(resolver: resolver)
        try await runtime.prime()
        let primed = await runtime.primedURL
        XCTAssertNotNil(primed)
        await runtime.unload()
        let cleared = await runtime.primedURL
        XCTAssertNil(cleared)
    }
}
