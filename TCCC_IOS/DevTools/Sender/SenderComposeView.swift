import SwiftUI

struct SenderComposeView: View {
    @Bindable var viewModel: SenderViewModel
    let onBack: () -> Void
    let onSend: () -> Void

    @State private var ambientMeter = AmbientMeter()
    @Environment(\.palette) private var palette

    init(
        viewModel: SenderViewModel,
        onBack: @escaping () -> Void = {},
        onSend: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onSend = onSend
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(alignment: .top, spacing: Layout.gridGap) {
                scriptPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                controlsPanel
                    .frame(minWidth: 340, maxWidth: 340, maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.bg)
        .task {
            await ambientMeter.start()
        }
        .onDisappear {
            ambientMeter.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                ambientMeter.stop()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.fg)
                    .frame(width: Layout.minHitTarget, height: Layout.minHitTarget)
                    .overlay(
                        Rectangle()
                            .strokeBorder(palette.line, lineWidth: Layout.hairline)
                    )
            }
            .buttonStyle(.plain)

            Text("DevTools")
                .tccc(.labelSmall)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)

            Rectangle()
                .fill(palette.line)
                .frame(width: Layout.hairline, height: 14)

            Text("Sender Compose")
                .tccc(.label)
                .foregroundStyle(palette.fg)
                .textCase(.uppercase)

            Spacer()

            Text(viewModel.selectedVoiceDisplayName)
                .tccc(.meta)
                .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, Layout.outerPadding)
        .frame(maxWidth: .infinity, minHeight: Layout.pageHeaderHeight + 10)
        .background(palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
    }

    private var scriptPanel: some View {
        Panel("Scenario Script", titleIcon: "doc.text", action: viewModel.estimatedReadingTimeLabel, padded: false) {
            VStack(spacing: 0) {
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                statsRow
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: Layout.hairline)
                    }
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.script.isEmpty {
                Text("Paste scenario script here.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.fg3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $viewModel.script)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.fg)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.bg)
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statChip(label: "Words", value: "\(viewModel.wordCount)")
            statChip(label: "Read", value: viewModel.estimatedReadingTimeLabel)
            statChip(label: "Rate", value: "\(SenderViewModel.readingWordsPerMinute) wpm")
            Spacer()
            Text("Device TTS")
                .tccc(.meta)
                .foregroundStyle(palette.fg3)
        }
        .padding(8)
        .background(palette.bg1)
    }

    private var controlsPanel: some View {
        Panel("Playback Setup", titleIcon: "speaker.wave.2", padded: true) {
            VStack(alignment: .leading, spacing: 12) {
                ambientPanel

                Divider()
                    .background(palette.line)

                voicePicker

                sliderRow(
                    label: "Speed",
                    value: String(format: "%.2fx", viewModel.speed),
                    binding: Binding(
                        get: { viewModel.speed },
                        set: { viewModel.setSpeed($0) }
                    ),
                    range: 0.7...1.3,
                    step: 0.05
                )

                sliderRow(
                    label: "Pitch",
                    value: String(format: "%+.1f st", viewModel.pitchSemitones),
                    binding: Binding(
                        get: { viewModel.pitchSemitones },
                        set: { viewModel.setPitchSemitones($0) }
                    ),
                    range: -2...2,
                    step: 0.1
                )

                sliderRow(
                    label: "Volume",
                    value: String(format: "%.0f%%", viewModel.volume * 100),
                    binding: Binding(
                        get: { viewModel.volume },
                        set: { viewModel.setVolume($0) }
                    ),
                    range: 0...1,
                    step: 0.05
                )

                Spacer(minLength: 8)

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                BigButton(
                    viewModel.isSending ? "Preparing" : "Send / Play",
                    systemImage: "play.fill",
                    style: .accent
                ) {
                    Task {
                        ambientMeter.stop()
                        if await viewModel.send() != nil {
                            onSend()
                        }
                    }
                }
                .disabled(!viewModel.canSend)
                .opacity(viewModel.canSend ? 1.0 : 0.45)
            }
        }
    }

    private var ambientPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ambient pre-roll")
                    .tccc(.labelSmall)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)
                Spacer()
                Text(String(format: "%.1f dBFS", ambientMeter.dBFS))
                    .tccc(.meta)
                    .foregroundStyle(ambientMeter.isSampling ? palette.accent : palette.fg3)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(palette.bg2)
                    Rectangle()
                        .fill(ambientMeter.isSampling ? palette.accent : palette.fg3)
                        .frame(width: proxy.size.width * ambientMeter.normalizedLevel)
                }
                .overlay(
                    Rectangle()
                        .strokeBorder(palette.line, lineWidth: Layout.hairline)
                )
            }
            .frame(height: 18)

            Text(ambientMeter.statusMessage)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(palette.bg)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

    private var voicePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voice")
                .tccc(.labelSmall)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)

            Picker("Voice", selection: $viewModel.selectedVoiceID) {
                ForEach(viewModel.availableVoices) { voice in
                    Text(voice.displayName).tag(voice.id)
                }
            }
            .pickerStyle(.menu)
            .tint(palette.accent)
            .frame(maxWidth: .infinity, minHeight: Layout.minHitTarget, alignment: .leading)
            .padding(.horizontal, 10)
            .background(palette.bg)
            .overlay(
                Rectangle()
                    .strokeBorder(palette.line, lineWidth: Layout.hairline)
            )
        }
    }

    private func sliderRow(
        label: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .tccc(.labelSmall)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)
                Spacer()
                Text(value)
                    .tccc(.meta)
                    .foregroundStyle(palette.fg)
            }

            Slider(value: binding, in: range, step: step)
                .tint(palette.accent)
                .frame(minHeight: Layout.minHitTarget)
        }
    }

    private func statChip(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .tccc(.labelTiny)
                .foregroundStyle(palette.fg3)
                .textCase(.uppercase)
            Text(value)
                .tccc(.meta)
                .foregroundStyle(palette.fg)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(palette.bg)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }
}

#Preview {
    SenderComposeView(viewModel: SenderViewModel())
        .environment(\.palette, Theme.dark.palette)
}
