import SwiftUI
import Speech
import TCCCBench
import TCCCExtractor

/// One-shot thread-safe latch so a callback that may fire multiple times
/// resumes a continuation exactly once.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

/// Launch-arg-gated benchmark screen (`--transcription-benchmark`).
/// File-ingestion mode: for every audio file in
/// Documents/TranscriptionBenchmark/fixtures/, run the on-device Apple
/// Speech lane (production request config via SpeechRequestFactory),
/// score against the bundled reference, and write JSON + markdown results
/// to Documents/TranscriptionBenchmark/results/. Every attempted fixture
/// persists an artifact — failed, empty, and unscored runs included — with
/// the run's completion evidence (termination, callback count, timing,
/// retained partial text) so incomplete captures stay observable.
struct TranscriptionBenchmarkView: View {
    @State private var status = "Starting transcription benchmark…"
    @State private var summary = ""

    static var shouldRun: Bool {
        ProcessInfo.processInfo.arguments.contains("--transcription-benchmark")
    }

    /// Crash-safe Speech authorization. Returns the current status without
    /// prompting when it's already determined; otherwise prompts once with a
    /// continuation guarded against double-resume (the system callback has
    /// been observed to fire more than once).
    private static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return current }
        return await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            let once = OnceFlag()
            SFSpeechRecognizer.requestAuthorization { status in
                if once.claim() { cont.resume(returning: status) }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("TRANSCRIPTION BENCHMARK").font(.headline)
                Text(status).font(.system(.body, design: .monospaced))
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.black)
        .foregroundStyle(Color.white)
        .task { await run() }
    }

    private func run() async {
        // Stage breadcrumb → results/_progress.txt, rewritten synchronously at
        // each stage so a hard crash (SIGTRAP etc.) leaves the last-reached
        // stage on disk for post-mortem via `devicectl copy from`.
        var crumbs: [String] = []
        var progressURL: URL?
        func mark(_ stage: String) {
            crumbs.append(stage)
            if let progressURL {
                try? ProtectedWrite.data(Data(crumbs.joined(separator: "\n").utf8), to: progressURL)
            }
        }
        do {
            let fm = FileManager.default
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let fixturesDir = docs.appendingPathComponent("TranscriptionBenchmark/fixtures", isDirectory: true)
            let resultsDir = docs.appendingPathComponent("TranscriptionBenchmark/results", isDirectory: true)
            try fm.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: resultsDir, withIntermediateDirectories: true)
            progressURL = resultsDir.appendingPathComponent("_progress.txt")
            mark("dirs-created")

            let audioExtensions = Set(["m4a", "wav", "caf", "aif", "aiff"])
            let fixtures = try fm.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
                .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            mark("fixtures-listed: \(fixtures.map { $0.lastPathComponent })")

            guard !fixtures.isEmpty else {
                status = "No fixtures. Copy audio into Documents/TranscriptionBenchmark/fixtures/ (devicectl copy) and relaunch."
                return
            }

            // Speech permission. Check the current status first and only
            // request when undetermined — SFSpeechRecognizer.requestAuthorization
            // can invoke its completion handler more than once, which would
            // resume a bare CheckedContinuation twice and trap (SIGTRAP). The
            // request path below is guarded so it resumes exactly once.
            mark("before-requestAuthorization")
            let auth: SFSpeechRecognizerAuthorizationStatus = await Self.speechAuthorization()
            mark("auth-status: \(auth.rawValue) (authorized=\(auth == .authorized))")
            guard auth == .authorized else {
                status = "Speech recognition not authorized (status \(auth.rawValue)). Grant in Settings › Privacy › Speech Recognition."
                return
            }

            var lines: [String] = []
            for fixture in fixtures {
                let slug = BenchmarkReference.slug(forFixture: fixture)
                status = "Transcribing \(fixture.lastPathComponent)…"
                let memBefore = MemoryStat.availableBytes().map { Double($0) / 1_048_576.0 }
                let startedAt = ISO8601DateFormatter().string(from: Date())
                mark("before-transcribe: \(slug)")
                let transcriber = AppleSpeechFileTranscriber()
                let result: BenchmarkRunResult
                do {
                    let completion = try await transcriber.transcribe(fileURL: fixture)
                    mark("after-transcribe: \(slug) termination=\(completion.termination.rawValue) callbacks=\(completion.callbackCount)")
                    let memAfter = MemoryStat.availableBytes().map { Double($0) / 1_048_576.0 }

                    var warnings: [String] = []
                    if !completion.isComplete {
                        warnings.append("run terminated by \(completion.termination.rawValue) — retained transcript is partial evidence, not recognizer finalization")
                    }
                    let hypothesis = completion.transcript
                    if hypothesis.isEmpty {
                        warnings.append("no transcript text captured")
                    }

                    var scoring: BenchmarkRunResult.Scoring?
                    let scoringStatus: String
                    if hypothesis.isEmpty {
                        scoringStatus = "unavailable — empty transcript"
                    } else if let ref = BenchmarkReference.load(slug: slug) {
                        status = "Scoring \(slug)…"
                        mark("before-scoring: \(slug)")
                        let folds = ref.sidecar.extraFolds
                        let refTokens = TokenNormalizer.tokens(ref.referenceText, extraFolds: folds)
                        let hypTokens = TokenNormalizer.tokens(hypothesis, extraFolds: folds)
                        let wer = WERScorer.score(reference: refTokens, hypothesis: hypTokens)
                        let recall = KeywordRecallScorer.score(
                            keywords: ref.sidecar.keywords, transcriptTokens: hypTokens, extraFolds: folds)

                        // Extraction: feed the cumulative transcript through a
                        // fresh engine, then map.
                        let engine = PatientStateEngine.standard()
                        await engine.processTranscript(hypothesis, timestamp: Date(timeIntervalSince1970: 0))
                        let snapshot = await engine.snapshot()
                        let actual = BenchStateMapper.map(snapshot["PATIENT_1"])
                        let extraction = ExtractionScorer.score(
                            expectations: ref.sidecar.fieldExpectations, actual: actual)
                        scoring = .init(wer: wer, keywordRecall: recall, extraction: extraction)
                        scoringStatus = "scored"
                    } else {
                        scoringStatus = "unavailable — no bundled reference (\(slug).txt)"
                        warnings.append("transcript captured but not scored")
                    }

                    result = BenchmarkRunResult(
                        backend: "appleSpeech",
                        mode: "file",
                        fixture: fixture.lastPathComponent,
                        startedAt: startedAt,
                        completion: completion,
                        scoring: scoring,
                        scoringStatus: scoringStatus,
                        warnings: warnings,
                        availableMemoryBeforeMB: memBefore,
                        availableMemoryAfterMB: memAfter
                    )
                } catch {
                    mark("transcribe-threw: \(slug): \(error)")
                    result = BenchmarkRunResult.notStarted(
                        backend: "appleSpeech",
                        mode: "file",
                        fixture: fixture.lastPathComponent,
                        startedAt: startedAt,
                        failureReason: error.localizedDescription,
                        availableMemoryBeforeMB: memBefore,
                        availableMemoryAfterMB: MemoryStat.availableBytes().map { Double($0) / 1_048_576.0 }
                    )
                }

                // Persist an artifact for every attempted fixture — failed,
                // empty, and unscored runs included.
                let stamp = Int(Date().timeIntervalSince1970)
                let outURL = resultsDir.appendingPathComponent("\(slug)-\(stamp).json")
                try ProtectedWrite.data(BenchmarkRunResult.encoder.encode(result), to: outURL)
                lines.append(BenchmarkSummaryFormatter.line(slug: slug, result: result))
            }
            mark("all-fixtures-done")
            let report = (
                ["termination=finalized records recognizer finalization only — it does not prove whole-file coverage", ""]
                + lines
            ).joined(separator: "\n")
            try ProtectedWrite.data(Data(report.utf8), to: resultsDir.appendingPathComponent("summary.md"))
            summary = report
            status = "Done. Pull Documents/TranscriptionBenchmark/results/."
        } catch {
            mark("CAUGHT-ERROR: \(error)")
            // Also drop a dedicated error file next to the breadcrumb.
            if let progressURL {
                let errURL = progressURL.deletingLastPathComponent().appendingPathComponent("_error.txt")
                try? ProtectedWrite.data(Data("\(error)".utf8), to: errURL)
            }
            status = "Benchmark failed: \(error.localizedDescription)"
        }
    }
}

/// Per-fixture run artifact, schema v2. Written for every attempted fixture:
/// the completion-evidence block (termination, finalization flag, callback
/// count, first/last hypothesis timing, retained text, warnings) is always
/// present; the scoring block is optional and its absence is explicit via
/// `scoringStatus` — no zero/perfect scores are invented for missing
/// evidence. Headline metrics are stored as explicit fields (correction #1)
/// so JSONEncoder encodes them — WERResult.wer, KeywordRecall.recall, and
/// ExtractionScore.passedCount/recall are computed properties and are
/// therefore omitted by the synthesized Codable encoder.
struct BenchmarkRunResult: Codable {
    struct Scoring {
        let wer: WERResult
        let keywordRecall: KeywordRecall
        let extraction: ExtractionScore
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    let schemaVersion: Int
    let backend: String
    let mode: String
    let fixture: String
    let startedAt: String
    // Completion evidence — present for every attempted fixture.
    /// finalized | timedOut | failed | cancelled | notStarted
    let termination: String
    /// Recognizer finalization evidence only — never whole-file-coverage proof.
    let recognizerFinalized: Bool
    let failureReason: String?
    let callbackCount: Int
    /// First hypothesis-bearing callback (schema-v1 key name kept for
    /// comparison against existing artifacts).
    let firstPartialLatencySec: Double?
    let lastHypothesisLatencySec: Double?
    let wallTimeSec: Double
    let hypothesis: String
    let warnings: [String]
    // Scoring — nil when unavailable; scoringStatus says why.
    let scoringStatus: String
    let wer: WERResult?
    let keywordRecall: KeywordRecall?
    let extraction: ExtractionScore?
    let werPercent: Double?
    let keywordRecallPercent: Double?
    let extractionRecallPercent: Double?
    let extractionPassed: Int?
    let extractionTotal: Int?
    let availableMemoryBeforeMB: Double?
    let availableMemoryAfterMB: Double?

    init(
        backend: String,
        mode: String,
        fixture: String,
        startedAt: String,
        completion: SpeechFileRunState.Completion,
        scoring: Scoring?,
        scoringStatus: String,
        warnings: [String],
        availableMemoryBeforeMB: Double?,
        availableMemoryAfterMB: Double?
    ) {
        self.schemaVersion = 2
        self.backend = backend
        self.mode = mode
        self.fixture = fixture
        self.startedAt = startedAt
        self.termination = completion.termination.rawValue
        self.recognizerFinalized = completion.isComplete
        self.failureReason = completion.failureReason
        self.callbackCount = completion.callbackCount
        self.firstPartialLatencySec = completion.firstHypothesisAt.map {
            $0.timeIntervalSince(completion.startedAt)
        }
        self.lastHypothesisLatencySec = completion.lastHypothesisAt.map {
            $0.timeIntervalSince(completion.startedAt)
        }
        self.wallTimeSec = completion.finishedAt.timeIntervalSince(completion.startedAt)
        self.hypothesis = completion.transcript
        self.warnings = warnings
        self.scoringStatus = scoringStatus
        self.wer = scoring?.wer
        self.keywordRecall = scoring?.keywordRecall
        self.extraction = scoring?.extraction
        self.werPercent = scoring.map { $0.wer.wer * 100 }
        self.keywordRecallPercent = scoring.map { $0.keywordRecall.recall * 100 }
        self.extractionRecallPercent = scoring.map { $0.extraction.recall * 100 }
        self.extractionPassed = scoring.map { $0.extraction.passedCount }
        self.extractionTotal = scoring.map { $0.extraction.fields.count }
        self.availableMemoryBeforeMB = availableMemoryBeforeMB
        self.availableMemoryAfterMB = availableMemoryAfterMB
    }

    /// Artifact for a fixture whose transcription never started (recognizer
    /// unavailable, on-device unsupported, overlapping run).
    static func notStarted(
        backend: String,
        mode: String,
        fixture: String,
        startedAt: String,
        failureReason: String,
        availableMemoryBeforeMB: Double?,
        availableMemoryAfterMB: Double?
    ) -> BenchmarkRunResult {
        BenchmarkRunResult(
            schemaVersion: 2,
            backend: backend,
            mode: mode,
            fixture: fixture,
            startedAt: startedAt,
            termination: "notStarted",
            recognizerFinalized: false,
            failureReason: failureReason,
            callbackCount: 0,
            firstPartialLatencySec: nil,
            lastHypothesisLatencySec: nil,
            wallTimeSec: 0,
            hypothesis: "",
            warnings: ["transcription did not start"],
            scoringStatus: "unavailable — transcription did not start",
            wer: nil,
            keywordRecall: nil,
            extraction: nil,
            werPercent: nil,
            keywordRecallPercent: nil,
            extractionRecallPercent: nil,
            extractionPassed: nil,
            extractionTotal: nil,
            availableMemoryBeforeMB: availableMemoryBeforeMB,
            availableMemoryAfterMB: availableMemoryAfterMB
        )
    }

    private init(
        schemaVersion: Int,
        backend: String,
        mode: String,
        fixture: String,
        startedAt: String,
        termination: String,
        recognizerFinalized: Bool,
        failureReason: String?,
        callbackCount: Int,
        firstPartialLatencySec: Double?,
        lastHypothesisLatencySec: Double?,
        wallTimeSec: Double,
        hypothesis: String,
        warnings: [String],
        scoringStatus: String,
        wer: WERResult?,
        keywordRecall: KeywordRecall?,
        extraction: ExtractionScore?,
        werPercent: Double?,
        keywordRecallPercent: Double?,
        extractionRecallPercent: Double?,
        extractionPassed: Int?,
        extractionTotal: Int?,
        availableMemoryBeforeMB: Double?,
        availableMemoryAfterMB: Double?
    ) {
        self.schemaVersion = schemaVersion
        self.backend = backend
        self.mode = mode
        self.fixture = fixture
        self.startedAt = startedAt
        self.termination = termination
        self.recognizerFinalized = recognizerFinalized
        self.failureReason = failureReason
        self.callbackCount = callbackCount
        self.firstPartialLatencySec = firstPartialLatencySec
        self.lastHypothesisLatencySec = lastHypothesisLatencySec
        self.wallTimeSec = wallTimeSec
        self.hypothesis = hypothesis
        self.warnings = warnings
        self.scoringStatus = scoringStatus
        self.wer = wer
        self.keywordRecall = keywordRecall
        self.extraction = extraction
        self.werPercent = werPercent
        self.keywordRecallPercent = keywordRecallPercent
        self.extractionRecallPercent = extractionRecallPercent
        self.extractionPassed = extractionPassed
        self.extractionTotal = extractionTotal
        self.availableMemoryBeforeMB = availableMemoryBeforeMB
        self.availableMemoryAfterMB = availableMemoryAfterMB
    }
}

/// Human-readable summary lines for summary.md and the on-screen report.
/// Scored and unscored runs share the completion-evidence tail (termination,
/// callback count, first/last hypothesis timing, wall time) so file-path
/// runs stay comparable; unscored runs state why scoring is unavailable and
/// how much hypothesis text was retained instead of inventing scores.
enum BenchmarkSummaryFormatter {
    static func line(slug: String, result: BenchmarkRunResult) -> String {
        var parts: [String] = []
        var head = "\(slug): \(result.termination)"
        if !result.recognizerFinalized { head += " INCOMPLETE" }
        parts.append(head)
        if let wer = result.wer, let recall = result.keywordRecall,
           let passed = result.extractionPassed, let total = result.extractionTotal {
            parts.append(String(
                format: "WER %.1f%% (S%d I%d D%d / N%d)",
                wer.wer * 100, wer.substitutions, wer.insertions, wer.deletions,
                wer.referenceCount))
            parts.append(String(
                format: "keywords %.0f%% (missed: %@)",
                recall.recall * 100,
                recall.misses.isEmpty ? "none" : recall.misses.joined(separator: ", ")))
            parts.append("extraction \(passed)/\(total)")
        } else {
            parts.append("scoring \(result.scoringStatus)")
            let words = result.hypothesis.split(whereSeparator: { $0.isWhitespace }).count
            parts.append("retained \(words) hypothesis words")
        }
        parts.append("callbacks \(result.callbackCount)")
        if let first = result.firstPartialLatencySec {
            parts.append(String(format: "first %.2fs", first))
        }
        if let last = result.lastHypothesisLatencySec {
            parts.append(String(format: "last %.2fs", last))
        }
        parts.append(String(format: "wall %.1fs", result.wallTimeSec))
        if let reason = result.failureReason {
            parts.append("reason: \(reason)")
        }
        return parts.joined(separator: " · ")
    }
}
