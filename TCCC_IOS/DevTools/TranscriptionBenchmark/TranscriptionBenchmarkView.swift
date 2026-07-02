import SwiftUI
import Speech
import TCCCBench
import TCCCExtractor

/// Launch-arg-gated benchmark screen (`--transcription-benchmark`).
/// File-ingestion mode: for every audio file in
/// Documents/TranscriptionBenchmark/fixtures/, run the on-device Apple
/// Speech lane (production request config via SpeechRequestFactory),
/// score against the bundled reference, and write JSON + markdown results
/// to Documents/TranscriptionBenchmark/results/.
struct TranscriptionBenchmarkView: View {
    @State private var status = "Starting transcription benchmark…"
    @State private var summary = ""

    static var shouldRun: Bool {
        ProcessInfo.processInfo.arguments.contains("--transcription-benchmark")
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
        do {
            let fm = FileManager.default
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let fixturesDir = docs.appendingPathComponent("TranscriptionBenchmark/fixtures", isDirectory: true)
            let resultsDir = docs.appendingPathComponent("TranscriptionBenchmark/results", isDirectory: true)
            try fm.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: resultsDir, withIntermediateDirectories: true)

            let audioExtensions = Set(["m4a", "wav", "caf", "aif", "aiff"])
            let fixtures = try fm.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
                .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !fixtures.isEmpty else {
                status = "No fixtures. Copy audio into Documents/TranscriptionBenchmark/fixtures/ (devicectl copy) and relaunch."
                return
            }

            // Speech permission (first run on a fresh install).
            let auth: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            guard auth == .authorized else {
                status = "Speech recognition not authorized."
                return
            }

            var lines: [String] = []
            for fixture in fixtures {
                let slug = BenchmarkReference.slug(forFixture: fixture)
                status = "Transcribing \(fixture.lastPathComponent)…"
                let memBefore = MemoryStat.availableBytes().map { Double($0) / 1_048_576.0 }
                let transcriber = AppleSpeechFileTranscriber()
                let output = try await transcriber.transcribe(fileURL: fixture)
                let memAfter = MemoryStat.availableBytes().map { Double($0) / 1_048_576.0 }
                guard !output.finals.isEmpty else {
                    lines.append("\(slug): FAILED — recognizer produced no finals")
                    continue
                }
                let hypothesis = output.finals.joined(separator: " ")

                guard let ref = BenchmarkReference.load(slug: slug) else {
                    lines.append("\(slug): no bundled reference (\(slug).txt) — transcript captured, not scored")
                    continue
                }
                status = "Scoring \(slug)…"
                let folds = ref.sidecar.extraFolds
                let refTokens = TokenNormalizer.tokens(ref.referenceText, extraFolds: folds)
                let hypTokens = TokenNormalizer.tokens(hypothesis, extraFolds: folds)
                let wer = WERScorer.score(reference: refTokens, hypothesis: hypTokens)
                let recall = KeywordRecallScorer.score(
                    keywords: ref.sidecar.keywords, transcriptTokens: hypTokens, extraFolds: folds)

                // Extraction: feed finals through a fresh engine, then map.
                let engine = PatientStateEngine.standard()
                var ts = Date(timeIntervalSince1970: 0)
                for final in output.finals {
                    await engine.processTranscript(final, timestamp: ts)
                    ts.addTimeInterval(5)
                }
                let snapshot = await engine.snapshot()
                let actual = BenchStateMapper.map(snapshot["PATIENT_1"])
                let extraction = ExtractionScorer.score(
                    expectations: ref.sidecar.fieldExpectations, actual: actual)

                let result = BenchmarkRunResult(
                    backend: "appleSpeech",
                    mode: "file",
                    fixture: fixture.lastPathComponent,
                    startedAt: ISO8601DateFormatter().string(from: Date()),
                    wer: wer,
                    keywordRecall: recall,
                    extraction: extraction,
                    firstPartialLatencySec: output.firstPartialLatencySec,
                    wallTimeSec: output.wallTimeSec,
                    availableMemoryBeforeMB: memBefore,
                    availableMemoryAfterMB: memAfter,
                    hypothesis: hypothesis
                )
                let stamp = Int(Date().timeIntervalSince1970)
                let outURL = resultsDir.appendingPathComponent("\(slug)-\(stamp).json")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(result).write(to: outURL)

                lines.append(String(
                    format: "%@: WER %.1f%% (S%d I%d D%d / N%d) · keywords %.0f%% (missed: %@) · extraction %d/%d · first partial %.2fs · wall %.1fs",
                    slug, wer.wer * 100, wer.substitutions, wer.insertions, wer.deletions,
                    wer.referenceCount, recall.recall * 100,
                    recall.misses.isEmpty ? "none" : recall.misses.joined(separator: ", "),
                    extraction.passedCount, extraction.fields.count,
                    output.firstPartialLatencySec ?? -1, output.wallTimeSec
                ))
            }
            let report = lines.joined(separator: "\n")
            try report.write(
                to: resultsDir.appendingPathComponent("summary.md"),
                atomically: true, encoding: .utf8)
            summary = report
            status = "Done. Pull Documents/TranscriptionBenchmark/results/."
        } catch {
            status = "Benchmark failed: \(error.localizedDescription)"
        }
    }
}

/// Per-fixture run result. All headline metrics are stored as explicit
/// fields (correction #1) so JSONEncoder encodes them — WERResult.wer,
/// KeywordRecall.recall, and ExtractionScore.passedCount/recall are all
/// computed properties and are therefore omitted by the synthesized
/// Codable encoder. The convenience stored fields below are computed
/// once at construction so the written JSON is self-describing.
struct BenchmarkRunResult: Codable {
    let backend: String
    let mode: String
    let fixture: String
    let startedAt: String
    let wer: WERResult
    let keywordRecall: KeywordRecall
    let extraction: ExtractionScore
    let firstPartialLatencySec: Double?
    let wallTimeSec: Double
    let availableMemoryBeforeMB: Double?
    let availableMemoryAfterMB: Double?
    let hypothesis: String
    // Correction #1: self-describing convenience fields stored at construction
    // so JSONEncoder emits the headline numbers (computed properties are not encoded).
    let werPercent: Double
    let keywordRecallPercent: Double
    let extractionRecallPercent: Double
    let extractionPassed: Int
    let extractionTotal: Int

    init(
        backend: String,
        mode: String,
        fixture: String,
        startedAt: String,
        wer: WERResult,
        keywordRecall: KeywordRecall,
        extraction: ExtractionScore,
        firstPartialLatencySec: Double?,
        wallTimeSec: Double,
        availableMemoryBeforeMB: Double?,
        availableMemoryAfterMB: Double?,
        hypothesis: String
    ) {
        self.backend = backend
        self.mode = mode
        self.fixture = fixture
        self.startedAt = startedAt
        self.wer = wer
        self.keywordRecall = keywordRecall
        self.extraction = extraction
        self.firstPartialLatencySec = firstPartialLatencySec
        self.wallTimeSec = wallTimeSec
        self.availableMemoryBeforeMB = availableMemoryBeforeMB
        self.availableMemoryAfterMB = availableMemoryAfterMB
        self.hypothesis = hypothesis
        // Derive headline numbers from the scoring structs at construction time.
        self.werPercent = wer.wer * 100
        self.keywordRecallPercent = keywordRecall.recall * 100
        self.extractionRecallPercent = extraction.recall * 100
        self.extractionPassed = extraction.passedCount
        self.extractionTotal = extraction.fields.count
    }
}
