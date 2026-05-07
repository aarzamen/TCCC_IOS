import SwiftUI
@preconcurrency import AVFoundation

struct SenderReadoutView: View {
    let viewModel: SenderViewModel
    let onBack: () -> Void
    let onReedit: () -> Void

    @Environment(\.palette) private var palette
    @StateObject private var playback = SenderReadoutPlaybackController()

    init(
        viewModel: SenderViewModel,
        onReedit: @escaping () -> Void,
        onBack: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onReedit = onReedit
        self.onBack = onBack ?? onReedit
    }

    var body: some View {
        HStack(spacing: Layout.gridGap) {
            textPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            playbackColumn
                .frame(width: 330)
        }
        .padding(Layout.outerPadding)
        .task(id: viewModel.readout?.id) {
            playback.configure(
                result: viewModel.readout?.synthesisResult,
                initialVolume: viewModel.readout?.volume ?? viewModel.volume
            )
        }
        .onDisappear {
            playback.close()
        }
    }

    private var textPanel: some View {
        Panel("Readout", titleIcon: "text.alignleft", action: scriptAction, padded: false) {
            ScrollView {
                Text(attributedScript)
                    .font(.system(size: 18, weight: .semibold))
                    .lineSpacing(7)
                    .foregroundStyle(palette.fg1)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(palette.bg)
        }
    }

    private var playbackColumn: some View {
        VStack(spacing: Layout.gridGap) {
            Panel("Playback", titleIcon: "waveform", action: playback.statusLabel) {
                VStack(alignment: .leading, spacing: 12) {
                    PlaybackVisualizer(
                        snapshot: playback.levelSnapshot,
                        isActive: playback.isPlaying
                    )

                    playbackStatus
                    scrubber
                    volumeSlider
                    transport
                }
            }

            Panel("Highlighting", titleIcon: "highlighter") {
                Text("Sentence-level highlighting follows rendered TTS timing. Without timings or audio, the full script stays static.")
                    .tccc(.bodyText)
                    .foregroundStyle(palette.fg2)
                    .lineLimit(4)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                BigButton("Back", systemImage: "chevron.left") {
                    playback.pause()
                    onBack()
                }

                BigButton("Re-edit", systemImage: "pencil") {
                    playback.pause()
                    onReedit()
                }
            }
        }
    }

    @ViewBuilder
    private var playbackStatus: some View {
        if viewModel.isSending {
            statusText("TTS synthesis starting.")
        } else if let message = viewModel.readout?.errorMessage ?? viewModel.errorMessage {
            statusText(message, warning: true)
        } else {
            switch playback.status {
            case .noAudio:
                statusText("Waiting for rendered audio.")
            case .loading:
                statusText("Loading rendered audio.")
            case .ready:
                statusText(readyStatusText)
            case .playing:
                statusText("Playing.")
            case .paused:
                statusText("Paused.")
            case .ended:
                statusText("Playback ended.")
            case .failed(let message):
                statusText(message, warning: true)
            }
        }
    }

    private var scrubber: some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(
                value: Binding(
                    get: { playback.currentTime },
                    set: { playback.seek(to: $0) }
                ),
                in: 0...max(playback.duration, 0.01)
            )
            .disabled(!playback.canScrub)
            .tint(palette.accent)
            .frame(minHeight: Layout.minHitTarget)

            HStack {
                Text(playback.formattedCurrentTime)
                    .tccc(.meta)
                    .foregroundStyle(palette.fg1)
                Spacer(minLength: 0)
                Text(totalTimeLabel)
                    .tccc(.meta)
                    .foregroundStyle(palette.fg2)
            }
        }
    }

    private var volumeSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Volume")
                    .tccc(.labelTiny)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Text(String(format: "%.0f%%", playback.volume * 100))
                    .tccc(.meta)
                    .foregroundStyle(palette.fg)
            }
            Slider(
                value: Binding(
                    get: { playback.volume },
                    set: { newValue in
                        playback.setVolume(newValue)
                        viewModel.setVolume(newValue)
                    }
                ),
                in: 0...1,
                step: 0.05
            )
            .tint(palette.accent)
            .frame(minHeight: Layout.minHitTarget)
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            transportButton(
                title: playback.isPlaying ? "Pause" : "Play",
                systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                isEnabled: playback.canPlayOrPause
            ) {
                playback.togglePlayPause()
            }

            transportButton(
                title: "Stop",
                systemImage: "stop.fill",
                isEnabled: playback.canStop
            ) {
                playback.stop()
            }
        }
    }

    private func transportButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .heavy))
                Text(title)
                    .tccc(.labelTiny)
                    .textCase(.uppercase)
            }
            .foregroundStyle(palette.fg)
            .frame(maxWidth: .infinity, minHeight: Layout.minHitTarget)
            .background(palette.bg2)
            .overlay(
                Rectangle()
                    .strokeBorder(palette.line, lineWidth: Layout.hairline)
            )
            .opacity(isEnabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func statusText(_ text: String, warning: Bool = false) -> some View {
        Text(text)
            .tccc(.bodyText)
            .foregroundStyle(warning ? palette.warn : palette.fg2)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var readyStatusText: String {
        guard let renderer = viewModel.readout?.synthesisResult?.rendererName, !renderer.isEmpty else {
            return "Audio ready."
        }
        return "Audio ready: \(renderer)."
    }

    private var attributedScript: AttributedString {
        var text = AttributedString(scriptText)
        text.foregroundColor = palette.fg1

        guard
            let highlightedRange,
            let attributedRange = Range(highlightedRange, in: text)
        else {
            return text
        }

        text[attributedRange].foregroundColor = palette.fg
        text[attributedRange].backgroundColor = palette.accentDim
        return text
    }

    private var highlightedRange: Range<String.Index>? {
        guard
            let timings = viewModel.readout?.synthesisResult?.sentenceTimings,
            !timings.isEmpty,
            playback.currentTime > 0,
            let timingIndex = timings.firstIndex(where: {
                playback.currentTime >= $0.startTime && playback.currentTime < $0.endTime
            })
        else {
            return nil
        }

        return sentenceRanges(in: scriptText).safeElement(at: timingIndex)?.range
    }

    private var scriptText: String {
        if let readout = viewModel.readout, !readout.script.isEmpty {
            return readout.script
        }
        let trimmed = viewModel.trimmedScript
        return trimmed.isEmpty ? "No scenario script loaded." : trimmed
    }

    private var scriptAction: String {
        "\(scriptText.split(whereSeparator: \.isWhitespace).count) WORDS"
    }

    private var totalTimeLabel: String {
        if playback.duration > 0 {
            return SenderReadoutPlaybackController.formatTime(playback.duration)
        }
        return SenderReadoutPlaybackController.formatTime(viewModel.readout?.estimatedDuration ?? 0)
    }

    private func sentenceRanges(in script: String) -> [ReadoutSentenceRange] {
        guard !script.isEmpty else { return [] }

        var output: [ReadoutSentenceRange] = []
        var start = script.startIndex
        var cursor = script.startIndex

        while cursor < script.endIndex {
            let character = script[cursor]
            if character == "." || character == "!" || character == "?" || character == "\n" {
                let end = script.index(after: cursor)
                appendSentenceRange(start..<end, in: script, to: &output)
                start = end
                while start < script.endIndex && script[start].isWhitespace {
                    start = script.index(after: start)
                }
                cursor = start
            } else {
                cursor = script.index(after: cursor)
            }
        }

        if start < script.endIndex {
            appendSentenceRange(start..<script.endIndex, in: script, to: &output)
        }

        return output
    }

    private func appendSentenceRange(
        _ range: Range<String.Index>,
        in script: String,
        to output: inout [ReadoutSentenceRange]
    ) {
        let piece = String(script[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return }

        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper && script[lower].isWhitespace {
            lower = script.index(after: lower)
        }
        while upper > lower {
            let beforeUpper = script.index(before: upper)
            if !script[beforeUpper].isWhitespace { break }
            upper = beforeUpper
        }

        output.append(ReadoutSentenceRange(range: lower..<upper))
    }
}

@MainActor
private final class SenderReadoutPlaybackController: ObservableObject {
    enum Status: Equatable {
        case noAudio
        case loading
        case ready
        case playing
        case paused
        case ended
        case failed(String)
    }

    @Published private(set) var status: Status = .noAudio
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var levelSnapshot: PlaybackLevelSnapshot = .inactive()
    @Published private(set) var volume: Double = 0.8

    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private var meterTask: Task<Void, Never>?

    var isPlaying: Bool {
        status == .playing
    }

    var canPlayOrPause: Bool {
        switch status {
        case .ready, .playing, .paused, .ended:
            player != nil
        default:
            false
        }
    }

    var canStop: Bool {
        switch status {
        case .playing, .paused, .ended:
            player != nil
        default:
            false
        }
    }

    var canScrub: Bool {
        player != nil && duration > 0
    }

    var statusLabel: String {
        switch status {
        case .noAudio: "No Audio"
        case .loading: "Loading"
        case .ready: "Ready"
        case .playing: "Playing"
        case .paused: "Paused"
        case .ended: "Ended"
        case .failed: "Failed"
        }
    }

    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }

    func configure(result: SenderSynthesisResult?, initialVolume: Double) {
        setVolume(initialVolume)

        guard let result else {
            close()
            status = .noAudio
            return
        }

        if loadedURL == result.audioURL {
            duration = max(result.duration, player?.duration ?? 0)
            return
        }

        close()
        status = .loading

        do {
            let nextPlayer = try AVAudioPlayer(contentsOf: result.audioURL)
            nextPlayer.isMeteringEnabled = true
            nextPlayer.volume = Float(volume)
            nextPlayer.prepareToPlay()
            player = nextPlayer
            loadedURL = result.audioURL
            currentTime = 0
            duration = max(result.duration, nextPlayer.duration)
            levelSnapshot = .inactive()
            status = .ready
        } catch {
            player = nil
            loadedURL = nil
            currentTime = 0
            duration = 0
            levelSnapshot = .inactive()
            status = .failed("Playback failed: \(error.localizedDescription)")
        }
    }

    func setVolume(_ newValue: Double) {
        let clamped = min(1, max(0, newValue.isFinite ? newValue : 0))
        volume = clamped
        player?.volume = Float(clamped)
    }

    func togglePlayPause() {
        if status == .playing {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let player else { return }
        if player.currentTime >= max(0, player.duration - 0.05) {
            player.currentTime = 0
        }
        player.volume = Float(volume)
        player.isMeteringEnabled = true
        player.play()
        status = .playing
        startMetering()
    }

    func pause() {
        guard let player else { return }
        player.pause()
        currentTime = player.currentTime
        status = .paused
        stopMetering(resetLevels: true)
    }

    func stop() {
        guard let player else { return }
        player.stop()
        player.currentTime = 0
        currentTime = 0
        status = .ready
        stopMetering(resetLevels: true)
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), max(0, player.duration))
        player.currentTime = clamped
        currentTime = clamped
        if status == .ended && clamped < player.duration {
            status = .ready
        }
    }

    func close() {
        stopMetering(resetLevels: true)
        player?.stop()
        player = nil
        loadedURL = nil
        currentTime = 0
        duration = 0
        status = .noAudio
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.meterTick()
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func stopMetering(resetLevels: Bool) {
        meterTask?.cancel()
        meterTask = nil
        if resetLevels {
            levelSnapshot = .inactive()
        }
    }

    private func meterTick() {
        guard let player else {
            stopMetering(resetLevels: true)
            return
        }

        currentTime = player.currentTime
        duration = player.duration

        guard player.isPlaying else {
            if status == .playing {
                currentTime = player.duration
                status = .ended
                stopMetering(resetLevels: true)
            }
            return
        }

        player.updateMeters()
        let channelCount = max(1, player.numberOfChannels)
        var averageTotal = 0.0
        var peakTotal = 0.0

        for channel in 0..<channelCount {
            averageTotal += Self.normalizedPower(player.averagePower(forChannel: channel))
            peakTotal += Self.normalizedPower(player.peakPower(forChannel: channel))
        }

        let average = averageTotal / Double(channelCount)
        let peak = peakTotal / Double(channelCount)
        levelSnapshot = levelSnapshot.appending(sample: average, peak: peak)
    }

    private static func normalizedPower(_ decibels: Float) -> Double {
        guard decibels.isFinite, decibels > -80 else { return 0 }
        return min(1, max(0, pow(10, Double(decibels) / 20)))
    }

    static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "00:00" }
        let seconds = Int(time.rounded(.down))
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct ReadoutSentenceRange {
    let range: Range<String.Index>
}

private extension Array {
    func safeElement(at index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    SenderReadoutView(viewModel: SenderViewModel(), onReedit: {})
        .environment(\.palette, .dark)
}
