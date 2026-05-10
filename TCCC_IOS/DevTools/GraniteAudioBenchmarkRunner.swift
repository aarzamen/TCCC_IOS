import AVFoundation
import SwiftUI
import TCCCAudio

struct GraniteAudioBenchmarkView: View {
    let state: AppState

    @State private var status = "Preparing Granite audio benchmark..."
    @State private var outputPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Granite Audio Benchmark")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            Text(status)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            if !outputPath.isEmpty {
                Text(outputPath)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .foregroundStyle(Color.white)
        .task {
            await runBenchmark()
        }
    }

    static var shouldRun: Bool {
        ProcessInfo.processInfo.arguments.contains("--granite-audio-benchmark")
    }

    private func runBenchmark() async {
        let runner = GraniteAudioBenchmarkRunner(
            bookmarkStore: state.graniteSpeechBookmarkStore
        ) { message in
            Task { @MainActor in
                self.status = message
            }
        }

        do {
            let output = try await runner.run()
            status = "Benchmark complete. Pull GraniteAudioBenchmark from Documents."
            outputPath = output.path
        } catch {
            status = "Benchmark failed: \(error.localizedDescription)"
        }
    }
}

private struct GraniteAudioBenchmarkRunner {
    typealias StatusSink = @Sendable (String) -> Void

    private let bookmarkStore: GraniteSpeechBookmarkStore
    private let status: StatusSink
    private let config: Config
    private let fileManager = FileManager.default

    init(
        bookmarkStore: GraniteSpeechBookmarkStore,
        status: @escaping StatusSink
    ) {
        self.bookmarkStore = bookmarkStore
        self.status = status
        self.config = Config.current()
    }

    func run() async throws -> URL {
        let root = try outputRoot()
        let runID = Self.timestamp()
        let runDirectory = root.appendingPathComponent("run-\(runID)", isDirectory: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let artifacts = Artifacts(runDirectory: runDirectory)
        do {
            try artifacts.writeStatus(.init(state: "running", detail: "starting", updatedAt: Date()))
            status("Running MLX slice probe...")

            let sliceProbe = MLXArraySliceProbe.run()
            try artifacts.writeJSON(sliceProbe, fileName: "slice-probe.json")

            try artifacts.writeStatus(.init(state: "running", detail: "discovering fixtures", updatedAt: Date()))
            let fixtures = try discoverFixtures(root: root)
            try artifacts.writeJSON(config, fileName: "config.json")
            try artifacts.writeMarkdown("# Granite Audio Benchmark\n\nRun: `\(runID)`\n\n")

            guard !fixtures.isEmpty else {
                throw BenchmarkError.noFixtures
            }

            let runtime = GraniteSpeechRuntime(
                resolver: GraniteSpeechModelResolver(
                    bookmarkStore: bookmarkStore,
                    hfCacheLookup: { modelID in
                        HFHubCache.directory(for: modelID).flatMap { directory in
                            HFHubCache.contains(modelId: modelID) ? directory : nil
                        }
                    }
                )
            )

            status("Priming Granite Speech model...")
            try artifacts.writeStatus(.init(state: "running", detail: "priming model", updatedAt: Date()))
            try await runtime.prime()
            let primeDelta = await runtime.primeMemoryDelta
            let source = await runtime.primedSource?.rawValue ?? "unknown"
            try artifacts.appendMarkdown("""
            ## Model
            - Resolver source: `\(source)`
            - Prime seconds: \(Self.format(primeDelta?.loadDurationSeconds ?? 0))
            - Prime footprint delta MB: \(Self.format(primeDelta?.physFootprintDeltaMB ?? 0))

            """)

            for fixture in fixtures {
                let duration = try audioDurationSeconds(fixture.url)
                status("Fixture \(fixture.name), \(Self.format(duration)) s...")

                let shouldRunSingle = config.includeSingleShot && duration <= config.singleShotMaxSeconds
                if shouldRunSingle {
                    let result = try await runStrategy(
                        runtime: runtime,
                        fixture: fixture,
                        durationSeconds: duration,
                        windowSeconds: nil,
                        overlapSeconds: 0,
                        artifacts: artifacts
                    )
                    try artifacts.append(result)
                }

                for window in config.windowsSeconds where window <= max(duration + 0.1, 0.1) {
                    let result = try await runStrategy(
                        runtime: runtime,
                        fixture: fixture,
                        durationSeconds: duration,
                        windowSeconds: window,
                        overlapSeconds: min(config.overlapSeconds, max(0, window / 2)),
                        artifacts: artifacts
                    )
                    try artifacts.append(result)
                }
            }

            await runtime.unload()
            try artifacts.writeStatus(.init(state: "complete", detail: "finished", updatedAt: Date()))
            return runDirectory
        } catch {
            try? artifacts.writeStatus(.init(state: "failed", detail: String(describing: error), updatedAt: Date()))
            throw error
        }
    }

    private func runStrategy(
        runtime: GraniteSpeechRuntime,
        fixture: Fixture,
        durationSeconds: Double,
        windowSeconds: Double?,
        overlapSeconds: Double,
        artifacts: Artifacts
    ) async throws -> StrategyResult {
        let strategyName = windowSeconds.map { "window-\(Self.format($0))s" } ?? "single-shot"
        status("\(fixture.name): \(strategyName)")

        let descriptors: [AudioChunkDescriptor]
        if let windowSeconds {
            let chunkDirectory = artifacts.runDirectory
                .appendingPathComponent("chunks-\(fixture.name)-\(Self.format(windowSeconds))s", isDirectory: true)
            descriptors = try makeChunks(
                sourceURL: fixture.url,
                chunkDirectory: chunkDirectory,
                windowSeconds: windowSeconds,
                overlapSeconds: overlapSeconds
            )
        } else {
            descriptors = [.singleShot(url: fixture.url, durationSeconds: durationSeconds)]
        }

        var chunkResults: [ChunkResult] = []
        var chunkTexts: [String] = []
        let strategyStart = Date()

        for descriptor in descriptors {
            status("\(fixture.name): \(strategyName) chunk \(descriptor.index + 1)/\(descriptors.count)")
            let result = try await transcribeChunk(
                runtime: runtime,
                descriptor: descriptor,
                strategyName: strategyName
            )
            chunkResults.append(result)
            chunkTexts.append(result.text)
            MLXMemoryProbe.clearCache()
        }

        let strategyEnd = Date()
        let stitched = Self.stitch(chunkTexts)
        let recall = Self.keywordRecall(stitched)
        let peakFootprint = chunkResults.map(\.peakFootprintBytes).max() ?? 0
        let peakMLX = chunkResults.map(\.peakMLXTotalBytes).max() ?? 0
        let p50Latency = Self.percentile(chunkResults.map(\.wallSeconds), p: 0.50)
        let p95Latency = Self.percentile(chunkResults.map(\.wallSeconds), p: 0.95)
        let medianTPS = Self.percentile(chunkResults.compactMap(\.tokensPerSecond), p: 0.50)

        let summary = StrategyResult(
            fixtureName: fixture.name,
            fixtureDurationSeconds: durationSeconds,
            strategyName: strategyName,
            windowSeconds: windowSeconds,
            overlapSeconds: overlapSeconds,
            chunkCount: descriptors.count,
            totalWallSeconds: strategyEnd.timeIntervalSince(strategyStart),
            p50ChunkWallSeconds: p50Latency,
            p95ChunkWallSeconds: p95Latency,
            medianTokensPerSecond: medianTPS,
            peakFootprintBytes: peakFootprint,
            peakMLXTotalBytes: peakMLX,
            keywordRecall: recall,
            chunkResults: chunkResults,
            stitchedTranscript: stitched
        )

        try artifacts.appendMarkdown(summary.markdown)
        return summary
    }

    private func transcribeChunk(
        runtime: GraniteSpeechRuntime,
        descriptor: AudioChunkDescriptor,
        strategyName: String
    ) async throws -> ChunkResult {
        let sampler = BenchmarkSampler()
        let sampleTask = Task {
            while !Task.isCancelled {
                await sampler.capture()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { sampleTask.cancel() }

        MLXMemoryProbe.resetPeak()
        await sampler.capture()

        let start = Date()
        let stream = try await runtime.transcribe(audioURL: descriptor.url)
        var firstTokenSeconds: Double?
        var text = ""
        var tokensPerSecond: Double?
        var generationTokenCount: Int?
        var prefillSeconds: Double?
        var generateSeconds: Double?

        for try await event in stream {
            await sampler.capture()
            switch event {
            case .token(let token):
                if firstTokenSeconds == nil {
                    firstTokenSeconds = Date().timeIntervalSince(start)
                }
                text += token
            case .info(let info):
                tokensPerSecond = info.tokensPerSecond
                generationTokenCount = info.generationTokenCount
                prefillSeconds = info.prefillTime
                generateSeconds = info.generateTime
            case .result(let output):
                if !output.text.isEmpty {
                    text = output.text
                }
            }
        }

        await sampler.capture()
        let end = Date()
        let sampleSummary = await sampler.summary()

        return ChunkResult(
            strategyName: strategyName,
            index: descriptor.index,
            startSeconds: descriptor.startSeconds,
            endSeconds: descriptor.endSeconds,
            audioDurationSeconds: descriptor.endSeconds - descriptor.startSeconds,
            wallSeconds: end.timeIntervalSince(start),
            firstTokenSeconds: firstTokenSeconds,
            tokensPerSecond: tokensPerSecond,
            generationTokenCount: generationTokenCount,
            prefillSeconds: prefillSeconds,
            generateSeconds: generateSeconds,
            peakFootprintBytes: sampleSummary.peakFootprintBytes,
            peakMLXActiveBytes: sampleSummary.peakMLXActiveBytes,
            peakMLXCacheBytes: sampleSummary.peakMLXCacheBytes,
            peakMLXTotalBytes: sampleSummary.peakMLXTotalBytes,
            text: text
        )
    }

    private func makeChunks(
        sourceURL: URL,
        chunkDirectory: URL,
        windowSeconds: Double,
        overlapSeconds: Double
    ) throws -> [AudioChunkDescriptor] {
        try? fileManager.removeItem(at: chunkDirectory)
        try fileManager.createDirectory(at: chunkDirectory, withIntermediateDirectories: true)

        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFramePosition(source.length)
        let windowFrames = max(1, AVAudioFramePosition((windowSeconds * sampleRate).rounded()))
        let overlapFrames = max(0, AVAudioFramePosition((overlapSeconds * sampleRate).rounded()))
        let stepFrames = max(1, windowFrames - overlapFrames)

        var descriptors: [AudioChunkDescriptor] = []
        var startFrame: AVAudioFramePosition = 0
        var index = 0

        while startFrame < totalFrames {
            let remaining = totalFrames - startFrame
            if index > 0, remaining <= overlapFrames {
                break
            }
            let frameCount = min(windowFrames, remaining)
            let capacity = AVAudioFrameCount(frameCount)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw BenchmarkError.bufferAllocationFailed
            }

            source.framePosition = startFrame
            try source.read(into: buffer, frameCount: capacity)

            let chunkURL = chunkDirectory.appendingPathComponent(
                String(format: "chunk-%03d.caf", index)
            )
            let writer = try AVAudioFile(
                forWriting: chunkURL,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            try writer.write(from: buffer)

            let endFrame = startFrame + AVAudioFramePosition(buffer.frameLength)
            descriptors.append(.init(
                index: index,
                url: chunkURL,
                startSeconds: Double(startFrame) / sampleRate,
                endSeconds: Double(endFrame) / sampleRate
            ))

            if endFrame >= totalFrames {
                break
            }
            startFrame += stepFrames
            index += 1
        }

        return descriptors
    }

    private func discoverFixtures(root: URL) throws -> [Fixture] {
        let docsFixtureDirectory = root.appendingPathComponent("fixtures", isDirectory: true)
        let allowed = Set(["wav", "caf", "aif", "aiff", "m4a"])
        let requested = config.fixtureNames

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: docsFixtureDirectory.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                let fileName = docsFixtureDirectory.lastPathComponent
                if requested.isEmpty || requested.contains(fileName) {
                    return [Fixture(name: fileName, url: docsFixtureDirectory)]
                }
                return []
            }

            let urls = try fileManager.contentsOfDirectory(
                at: docsFixtureDirectory,
                includingPropertiesForKeys: nil
            )
            let matches = urls
                .filter { allowed.contains($0.pathExtension.lowercased()) }
                .filter { requested.isEmpty || requested.contains($0.lastPathComponent) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if !matches.isEmpty {
                return matches.map { Fixture(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            }
        }

        if let bundleFixture = Bundle.main.url(forResource: "test_5min", withExtension: "wav") {
            return [Fixture(name: "bundle-test_5min", url: bundleFixture)]
        }
        return []
    }

    private func audioDurationSeconds(_ url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private func outputRoot() throws -> URL {
        let docs = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = docs.appendingPathComponent("GraniteAudioBenchmark", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func stitch(_ texts: [String]) -> String {
        texts.reduce("") { current, next in
            merge(current, next)
        }
    }

    private static func merge(_ previous: String, _ next: String) -> String {
        let previousWords = previous.split(separator: " ").map(String.init)
        let nextWords = next.split(separator: " ").map(String.init)
        guard !previousWords.isEmpty else { return nextWords.joined(separator: " ") }
        guard !nextWords.isEmpty else { return previousWords.joined(separator: " ") }

        let limit = min(24, previousWords.count, nextWords.count)
        var overlap = 0
        if limit > 0 {
            for count in stride(from: limit, through: 1, by: -1) {
                let suffix = previousWords.suffix(count).map { $0.lowercased() }
                let prefix = nextWords.prefix(count).map { $0.lowercased() }
                if Array(suffix) == Array(prefix) {
                    overlap = count
                    break
                }
            }
        }
        return (previousWords + nextWords.dropFirst(overlap)).joined(separator: " ")
    }

    private static func keywordRecall(_ text: String) -> KeywordRecall {
        let tokens = [
            "8734", "9120", "44.50", "Reaper", "urgent surgical",
            "GSW", "chest", "AVPU P", "pain", "SpO2",
            "88", "93", "TXA", "Hextend", "chest seal",
            "needle decompression", "NKDA", "Dawson", "RD6942", "6942"
        ]
        let hits = tokens.filter { text.range(of: $0, options: .caseInsensitive) != nil }
        let missing = tokens.filter { !hits.contains($0) }
        return KeywordRecall(
            hitCount: hits.count,
            totalCount: tokens.count,
            percent: tokens.isEmpty ? 0 : Double(hits.count) / Double(tokens.count) * 100.0,
            hits: hits,
            missing: missing
        )
    }

    private static func percentile(_ values: [Double], p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private actor BenchmarkSampler {
    private var peakFootprintBytes: UInt64 = 0
    private var peakMLXActiveBytes: Int = 0
    private var peakMLXCacheBytes: Int = 0
    private var peakMLXTotalBytes: Int = 0

    func capture() {
        let process = MemoryMonitor.reading()
        let mlx = MLXMemoryProbe.reading()
        peakFootprintBytes = max(peakFootprintBytes, process.physFootprintBytes)
        peakMLXActiveBytes = max(peakMLXActiveBytes, mlx.activeBytes)
        peakMLXCacheBytes = max(peakMLXCacheBytes, mlx.cacheBytes)
        peakMLXTotalBytes = max(peakMLXTotalBytes, mlx.activeBytes + mlx.cacheBytes)
    }

    func summary() -> SampleSummary {
        SampleSummary(
            peakFootprintBytes: peakFootprintBytes,
            peakMLXActiveBytes: peakMLXActiveBytes,
            peakMLXCacheBytes: peakMLXCacheBytes,
            peakMLXTotalBytes: peakMLXTotalBytes
        )
    }
}

private struct Config: Codable, Sendable {
    let windowsSeconds: [Double]
    let overlapSeconds: Double
    let includeSingleShot: Bool
    let singleShotMaxSeconds: Double
    let fixtureNames: Set<String>

    static func current() -> Config {
        let environment = ProcessInfo.processInfo.environment
        return Config(
            windowsSeconds: parseDoubles(environment["GRANITE_AUDIO_BENCH_WINDOWS"]) ?? [4, 8, 10, 15],
            overlapSeconds: Double(environment["GRANITE_AUDIO_BENCH_OVERLAP"] ?? "") ?? 1.0,
            includeSingleShot: environment["GRANITE_AUDIO_BENCH_INCLUDE_SINGLE"] != "0",
            singleShotMaxSeconds: Double(environment["GRANITE_AUDIO_BENCH_SINGLE_MAX_SECONDS"] ?? "") ?? 20.0,
            fixtureNames: Set(parseStrings(environment["GRANITE_AUDIO_BENCH_FIXTURES"]))
        )
    }

    private static func parseDoubles(_ value: String?) -> [Double]? {
        guard let value, !value.isEmpty else { return nil }
        let parsed = value
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
        return parsed.isEmpty ? nil : parsed
    }

    private static func parseStrings(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct Fixture: Sendable {
    let name: String
    let url: URL
}

private struct AudioChunkDescriptor: Sendable {
    let index: Int
    let url: URL
    let startSeconds: Double
    let endSeconds: Double

    static func singleShot(url: URL, durationSeconds: Double) -> AudioChunkDescriptor {
        AudioChunkDescriptor(index: 0, url: url, startSeconds: 0, endSeconds: durationSeconds)
    }
}

private struct SampleSummary: Codable, Sendable {
    let peakFootprintBytes: UInt64
    let peakMLXActiveBytes: Int
    let peakMLXCacheBytes: Int
    let peakMLXTotalBytes: Int
}

private struct KeywordRecall: Codable, Sendable {
    let hitCount: Int
    let totalCount: Int
    let percent: Double
    let hits: [String]
    let missing: [String]
}

private struct ChunkResult: Codable, Sendable {
    let strategyName: String
    let index: Int
    let startSeconds: Double
    let endSeconds: Double
    let audioDurationSeconds: Double
    let wallSeconds: Double
    let firstTokenSeconds: Double?
    let tokensPerSecond: Double?
    let generationTokenCount: Int?
    let prefillSeconds: Double?
    let generateSeconds: Double?
    let peakFootprintBytes: UInt64
    let peakMLXActiveBytes: Int
    let peakMLXCacheBytes: Int
    let peakMLXTotalBytes: Int
    let text: String
}

private struct StrategyResult: Codable, Sendable {
    let fixtureName: String
    let fixtureDurationSeconds: Double
    let strategyName: String
    let windowSeconds: Double?
    let overlapSeconds: Double
    let chunkCount: Int
    let totalWallSeconds: Double
    let p50ChunkWallSeconds: Double?
    let p95ChunkWallSeconds: Double?
    let medianTokensPerSecond: Double?
    let peakFootprintBytes: UInt64
    let peakMLXTotalBytes: Int
    let keywordRecall: KeywordRecall
    let chunkResults: [ChunkResult]
    let stitchedTranscript: String

    var markdown: String {
        """
        ## \(fixtureName) - \(strategyName)
        - Fixture duration: \(String(format: "%.2f", fixtureDurationSeconds)) s
        - Chunks: \(chunkCount)
        - Total wall: \(String(format: "%.2f", totalWallSeconds)) s
        - p50 chunk wall: \(p50ChunkWallSeconds.map { String(format: "%.2f", $0) } ?? "-") s
        - p95 chunk wall: \(p95ChunkWallSeconds.map { String(format: "%.2f", $0) } ?? "-") s
        - Median tokens/s: \(medianTokensPerSecond.map { String(format: "%.2f", $0) } ?? "-")
        - Peak phys_footprint: \(String(format: "%.1f", Double(peakFootprintBytes) / 1_048_576.0)) MB
        - Peak MLX active+cache: \(String(format: "%.1f", Double(peakMLXTotalBytes) / 1_048_576.0)) MB
        - Keyword recall: \(keywordRecall.hitCount)/\(keywordRecall.totalCount) (\(String(format: "%.1f", keywordRecall.percent))%)
        - Missing: \(keywordRecall.missing.isEmpty ? "-" : keywordRecall.missing.joined(separator: ", "))
        - Transcript:
        ```
        \(stitchedTranscript)
        ```

        """
    }
}

private struct BenchmarkStatus: Codable, Sendable {
    let state: String
    let detail: String
    let updatedAt: Date
}

private struct Artifacts {
    let runDirectory: URL
    private let encoder: JSONEncoder
    private let lineEncoder: JSONEncoder
    private let fileManager = FileManager.default

    init(runDirectory: URL) {
        self.runDirectory = runDirectory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let lineEncoder = JSONEncoder()
        lineEncoder.outputFormatting = [.sortedKeys]
        lineEncoder.dateEncodingStrategy = .iso8601
        self.lineEncoder = lineEncoder
    }

    func writeStatus(_ status: BenchmarkStatus) throws {
        try writeJSON(status, fileName: "STATUS.json")
    }

    func writeJSON<T: Encodable>(_ value: T, fileName: String) throws {
        let data = try encoder.encode(value)
        try data.write(to: runDirectory.appendingPathComponent(fileName), options: .atomic)
    }

    func append(_ result: StrategyResult) throws {
        let data = try lineEncoder.encode(result)
        let url = runDirectory.appendingPathComponent("strategy-results.jsonl")
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))
    }

    func writeMarkdown(_ text: String) throws {
        try text.write(to: markdownURL, atomically: true, encoding: .utf8)
    }

    func appendMarkdown(_ text: String) throws {
        if !fileManager.fileExists(atPath: markdownURL.path) {
            fileManager.createFile(atPath: markdownURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: markdownURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private var markdownURL: URL {
        runDirectory.appendingPathComponent("SUMMARY.md")
    }
}

private enum BenchmarkError: LocalizedError {
    case noFixtures
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .noFixtures:
            return "No benchmark fixtures found in Documents/GraniteAudioBenchmark/fixtures or bundle."
        case .bufferAllocationFailed:
            return "Could not allocate an audio chunk buffer."
        }
    }
}
