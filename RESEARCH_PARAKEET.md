# Parakeet ASR on iPhone 17 Pro — Feasibility Research for TCCC.ai

**Date:** 2026-05-05
**Target device:** iPhone 17 Pro (A19 Pro, 12 GB RAM, iOS 26.2)
**Constraint set:** RF Ghost (no network at runtime), SideStore distribution, on-device only
**Existing pipeline:** `TCCC_IOS/Audio/TranscriptStream.swift` — protocol-based, decoupled from `SFSpeechRecognizer`

## TL;DR

**Yes — Parakeet on iPhone is a beaten path as of late 2025.** A turn-key Swift SDK ([FluidAudio](https://github.com/FluidInference/FluidAudio), Apache 2.0) compiles NVIDIA's Parakeet checkpoints to CoreML and runs them on the Apple Neural Engine (ANE). Batch RTFx of ~110× on M4 Pro and ~190× on M4 Pro for v3 is reported; on iPhone 17 Pro the ANE has been measured (Argmax) as 4.3× faster than the GPU for Parakeet v3. Working memory on ANE is ~66 MB (vs ~2 GB for the same weights on GPU via MLX).

**Recommended path: drop in `FluidAudio` + the `parakeet-tdt-0.6b-v2` (English-only) CoreML build, write a thin `ParakeetTranscriptStream` actor that adapts `StreamingEouAsrManager` (or `SlidingWindowAsrManager`) to your existing `TranscriptStream` protocol.** This is the lowest-risk way to validate the accuracy hypothesis end-to-end before committing to a custom port.

**License caveat for SideStore personal use:** v2 (English) and v3 are CC-BY-4.0 from NVIDIA → re-released as Apache 2.0 by FluidInference; commercial use is fine for both. The 120M EOU streaming variant (`parakeet-realtime-eou-120m-v1`) ships under the **NVIDIA Open Model License**, not CC-BY-4.0 — still permits commercial and personal use but with different attribution wording.

---

## 1. Parakeet Model Variants (English-Only Focus)

NVIDIA has shipped multiple Parakeet families. Relevant English checkpoints in 2025:

| Variant | Params | License | Release | English WER (Open ASR Leaderboard avg) | Notes |
|---|---|---|---|---|---|
| **parakeet-tdt-0.6b-v2** | 600M | CC-BY-4.0 | May 2025 | **6.05%** (LibriSpeech-clean 1.69%) | English-only, FastConformer-XL + TDT decoder, automatic punctuation + capitalization, word-level timestamps, up to 24 min audio in single pass |
| parakeet-tdt-0.6b-v3 | 600M | CC-BY-4.0 | Aug 2025 | ~5.4% English | 25 European languages; English slightly worse than v2 |
| parakeet-rnnt-1.1b | 1.1B | CC-BY-4.0 | 2024 | ~6.5% | Larger, slower than v2 — no benefit for English |
| parakeet-ctc-1.1b | 1.1B | CC-BY-4.0 | 2024 | Higher WER than RNNT | CTC decoder; only worth considering for streaming if EOU below isn't suitable |
| **parakeet-realtime-eou-120m-v1** | 120M | **NVIDIA Open Model License** | Late 2025 | 4.87% @ 320ms / 8.29% @ 160ms (LibriSpeech-clean) | English-only; **streaming-native** with built-in `<EOU>` end-of-utterance token; **no punctuation, no capitalization** |

**For TCCC** the choice is between **v2 (offline, batch+sliding window, has punctuation)** and **120m EOU (true streaming, lower latency, no punctuation)**. The Live Capture screen of TCCC.ai already debounces partials at 1.5 s and runs the engine on committed text — that pattern fits both options. v2 will give richer transcripts (capitalization helps the ZMIST narrative); EOU-120M will give snappier UI feedback.

Sources: [parakeet-tdt-0.6b-v2 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2), [parakeet-realtime-eou-120m-v1 CoreML repo](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml), [NVIDIA Parakeet-TDT blog](https://developer.nvidia.com/blog/turbocharge-asr-accuracy-and-speed-with-nvidia-nemo-parakeet-tdt/).

## 2. iOS Deployment Paths — From NeMo Checkpoint to On-Device Inference

| Path | Status (May 2026) | Verdict |
|---|---|---|
| **NeMo → ONNX → ONNX Runtime on iOS** | Possible (microsoft/onnxruntime-swift exists) but the TDT decoder requires custom op handling; nobody has published a clean iOS reference | **Skip** unless FluidAudio path fails |
| **NeMo → CoreMLTools direct conversion** | The hard part is splitting encoder/decoder/joint and the streaming state cache. FluidInference already did this work. | **Skip; reuse FluidInference output** |
| **MLX-Swift port** | [`senstella/parakeet-mlx`](https://github.com/senstella/parakeet-mlx) (Python) and [`FluidInference/swift-parakeet-mlx`](https://github.com/FluidInference/swift-parakeet-mlx) (Swift) exist. Swift MLX port is **archived July 2025** in favor of CoreML. ~2 GB working memory on GPU vs ~66 MB on ANE. | **Skip** — MLX path was abandoned for good reasons |
| **C++/Rust port** | [`Frikallo/parakeet.cpp`](https://github.com/Frikallo/parakeet.cpp) (MPS+Unified Memory, macOS-leaning) and [`altunenes/parakeet-rs`](https://github.com/altunenes/parakeet-rs) exist. Neither is iOS-ready out of the box. | **Skip** — viable as a backup if Apple deprecates ANE access patterns |
| **FluidAudio (CoreML on ANE)** | Apache 2.0 SwiftPM, v0.14.4 as of May 2026. Ships pre-converted `.mlmodelc` for v2, v3, and EOU 120M. iOS 17+ baseline (some features iOS 18+). [`fikrikarui/volocal`](https://github.com/fikrikarim/volocal) is a public iOS app using it for streaming. | **Use this** |
| Riva NIM | Server-side only — needs network. | **Forbidden** by RF Ghost |

Sources: [FluidAudio repo](https://github.com/FluidInference/FluidAudio), [parakeet-tdt-0.6b-v2-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml), [Whisper to Parakeet on Neural Engine](https://macparakeet.com/blog/whisper-to-parakeet-neural-engine/), [volocal](https://github.com/fikrikarui/volocal), [Argmax iPhone 17 benchmarks](https://www.argmaxinc.com/blog/iphone-17-on-device-inference-benchmarks).

## 3. Performance Expectations on iPhone 17 Pro

**Public Apple-Silicon numbers (M-class, batch transcription):**

- v2 / v3 on M4 Pro: ~110–190× RTFx via FluidAudio (CoreML on ANE)
- v2 on M-series via MLX: ~2 GB working memory, lower throughput, archived

**iPhone-class numbers:**

- iPhone 17 Pro GPU: 2.5–3.1× faster than iPhone 16 Pro GPU for Parakeet v3 (Argmax)
- iPhone 16 Pro: ANE is **4.3× faster than GPU** for Parakeet v3
- iPhone 17 Pro ANE delta over iPhone 16 Pro ANE: only 1.0–1.15× (Apple has not majorly upgraded the ANE this cycle)
- Streaming EOU (320 ms chunks) on M2: **12.48× RTFx, 4.87% WER on LibriSpeech-clean**
- Streaming EOU (160 ms chunks) on M2: **4.78× RTFx, 8.29% WER**

**Extrapolating to iPhone 17 Pro (A19 Pro):** Conservatively assume A19 Pro ANE ~= M2 ANE for this kind of FastConformer workload (the A19 Pro ANE is similar in TOPS to A18 Pro and A17 Pro at 35 TOPS; throughput in CoreML for ConvNet-Transformer hybrids is largely memory-bandwidth bound, not TOPS bound). Realistic expectations:

- v2 batch transcription on iPhone 17 Pro ANE: 30–60× RTFx (1 minute of audio in 1–2 seconds)
- EOU 120M streaming on iPhone 17 Pro ANE at 320 ms chunks: 8–15× RTFx, sub-400 ms perceived end-of-utterance latency
- Working memory: ~80–150 MB total (66 MB for the v3 weights; encoder runtime caches add ~50 MB; the EOU 120M is ~5× smaller)

**Disk footprint:**

- v2 CoreML repo: ~2.58 GB total (encoder + decoder + joint + preprocessor + 4-bit quantized variants). The actually loaded model is smaller — the repo carries multiple variants. Volocal reports **~450 MB** for the EOU 120M deployed bundle.
- Parakeet v3 ANE working memory cited at 66 MB by FluidInference

**Battery impact:** No public figures. Inference on ANE is dramatically more power-efficient than GPU (the whole point of the 4.3× speedup at lower power) and far more efficient than running `SFSpeechRecognizer` which keeps the CPU+ANE busy on Apple's own pipeline. For a 4-hour field session of intermittent transcription it should be in the same order of magnitude or better than current behavior. **This is the one number that needs an actual on-device measurement** — Instruments Energy Log on a 30-minute scenario.

## 4. License Gotchas

| Component | License | SideStore personal use | Sharing the IPA |
|---|---|---|---|
| Parakeet v2 weights (NVIDIA upstream) | CC-BY-4.0 | Fine | Fine — must include CC-BY attribution |
| Parakeet v3 weights (NVIDIA upstream) | CC-BY-4.0 | Fine | Fine — must include CC-BY attribution |
| Parakeet EOU 120M weights (NVIDIA upstream) | NVIDIA Open Model License | Fine | Fine — must include the NOML notice text and a copy of the license; commercial use explicitly granted |
| FluidInference CoreML conversions | Apache 2.0 | Fine | Fine — preserve copyright + license |
| FluidAudio Swift SDK | Apache 2.0 | Fine | Fine |
| `parakeet-mlx` reference | Apache 2.0 | Fine | Fine |

**Practical takeaways:**

1. **No NonCommercial or NoDerivatives clauses anywhere on this stack.** Personal SideStore deployment is unambiguously allowed.
2. **CC-BY-4.0 attribution requirement is real but trivial:** an in-app Settings → About panel listing "ASR powered by NVIDIA Parakeet (CC-BY-4.0). FluidAudio (Apache 2.0)." satisfies it.
3. **NVIDIA Open Model License (EOU only)** adds: include the license text and the literal notice "Licensed by NVIDIA Corporation under the NVIDIA Open Model License" in distributed builds. It also has an export-control compliance clause and a guardrail-circumvention termination clause — neither relevant to a medical-documentation app.
4. **No restriction on military, dual-use, or medical applications** in any of the licenses. The only thing to flag: NOML invokes NVIDIA's "Trustworthy AI terms" by reference — a generic responsible-use clause, not a medical-device prohibition.

Sources: [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/), [parakeet-tdt-0.6b-v2 license](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2), [parakeet-realtime-eou-120m-coreml](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml).

## 5. Integration Sketch — `ParakeetTranscriptStream`

The existing `TranscriptStream` protocol in `/Users/ama/TCCC_IOS/TCCC_IOS/Audio/TranscriptStream.swift`:

```swift
protocol TranscriptStream: Sendable {
    func authorize() async throws
    func prime() async throws
    func unprime() async
    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate>
    func stop() async
    func stopImmediate() async
}
```

A FluidAudio-backed implementation maps cleanly. Pseudocode:

```swift
import FluidAudio
import AVFoundation

actor ParakeetTranscriptStream: TranscriptStream {
    private var asr: StreamingEouAsrManager?       // or SlidingWindowAsrManager for v2
    private var engine: AVAudioEngine?
    private var fileWriter: AVAudioFile?
    private var emit: AsyncStream<RecognitionUpdate>.Continuation?
    private let modelDir: URL                      // pre-bundled or downloaded once

    func authorize() async throws {
        // Mic permission via AVAudioApplication.requestRecordPermission
        // No "speech" entitlement needed — Parakeet is just CoreML + audio.
    }

    func prime() async throws {
        let mgr = StreamingEouAsrManager(
            configuration: .default,
            chunkSize: .ms320,        // 320 ms = best WER/latency tradeoff
            eouDebounceMs: 600        // leave generous for combat-pace speech
        )
        try await mgr.loadModels(modelDir: modelDir)
        mgr.setEouCallback { [weak self] in
            // emits a RecognitionUpdate(isFinal: true) on each EOU token
        }
        self.asr = mgr
    }

    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate> {
        let (stream, cont) = AsyncStream<RecognitionUpdate>.makeStream()
        self.emit = cont

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)        // device-native rate
        // 16 kHz mono Float32 is what Parakeet expects — convert via AudioConverter
        let converter = AudioConverter(target: .parakeet16kMonoF32)

        if let url = audioURL {
            self.fileWriter = try AVAudioFile(forWriting: url, settings: format.settings)
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            Task { [weak self] in
                guard let self else { return }
                try? self.fileWriter?.write(from: buf)
                let f32 = converter.convertToFloat32Mono16k(buf)
                // Parakeet ingests Float32 chunks. Partial transcripts are returned
                // synchronously by `process` for each chunk; finals fire via the EOU callback.
                if let partial = try? await self.asr?.process(audioBuffer: f32),
                   !partial.isEmpty {
                    self.emit?.yield(.init(text: partial, isFinal: false, timestamp: .now))
                }
            }
        }
        try engine.start()
        self.engine = engine
        return stream
    }

    func stop() async {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        if let final = try? await asr?.finish(), !final.isEmpty {
            emit?.yield(.init(text: final, isFinal: true, timestamp: .now))
        }
        emit?.finish()
        await asr?.reset()
    }

    func stopImmediate() async { await stop() }
    func unprime() async { /* drop model from memory */ }
}
```

**Key semantic differences vs the current `SpeechRecognizer`:**

- No `requiresOnDeviceRecognition = true` flag — Parakeet *is* on-device by construction; there is no cloud fallback to disable.
- No 60-second auto-cutoff like Apple Speech.
- Audio format: 16 kHz mono Float32 strictly (`AudioConverter` from FluidAudio handles arbitrary input formats).
- Partial vs final result distinction comes from the EOU callback (final) vs `process()` return values (partial).
- No 10-second pre-roll constraint — you can keep priming the engine indefinitely. Your existing pre-roll buffer still helps for the audio file.

## 6. Comparison vs Apple Speech

**Where Parakeet should win for TCCC use:**

- **Drug names and medical anatomy.** Parakeet v2 was trained on 120k hours of speech including LibriSpeech, Fisher Corpus, Common Voice, AMI, and 110k hours of YouTube/YODAS pseudo-labels. Independent benchmarks (United-MedASR, Ionio 2025 Edge STT benchmark) report Parakeet has the **lowest deletion rate** under clean conditions (0.414 deletion errors) — which is exactly the failure mode that hurts in medicine ("I gave 10 mg of [silently dropped 'morphine']"). v2 LibriSpeech-clean at 1.69% WER is below WhisperKit Large-v3 Turbo at 2.2% WER on the same set.
- **Punctuation and capitalization** are emitted natively. SFSpeechRecognizer does not produce reliable punctuation in continuous medical-style narration.
- **No silent cloud fallback.** SFSpeechRecognizer with `requiresOnDeviceRecognition = true` *should* be on-device but the model varies by locale and device, and accuracy on technical vocabulary is what users complain about. Parakeet weights are explicit and checkable.
- **Long sessions.** Parakeet has no 1-minute hard cutoff. Field encounters can run continuously for the full episode.

**Where Parakeet may lose / where to hedge:**

- **Specialized military jargon and brand-name drugs** are not in any general ASR training set. Parakeet's deletion-rate advantage helps but won't save "ChitoGauze," "Quikclot Combat Gauze," "Tactical Combat Casualty Care," or unit nicknames. If accuracy on these terms is the key complaint, **the right next step beyond raw Parakeet is a small NeMo fine-tune on combat-medic vocabulary** — but that's months of data work, not days.
- **Speaker variability under stress** (yelling, gas mask, hearing protection). No public benchmark data. This will need real testing.
- **No voice-activity detection built into v2** the same way Apple's pipeline has. FluidAudio's EOU 120M model is the answer here, but it's a separate model from v2 — you'd run v2 for accuracy and EOU-120M for endpointing in parallel, OR pick EOU-120M alone and accept the lack of punctuation.
- **First-run download.** v2 is ~2.58 GB of CoreML files, EOU 120M is ~450 MB. SideStore re-signing happens locally, but the model needs to land on the device once. Either bundle in the IPA (bigger app) or download once on first launch over a trusted Wi-Fi (this is a setup-time exception to RF Ghost — flag it explicitly in onboarding).

Sources: [Whisper vs Parakeet on Apple Silicon](https://macparakeet.com/blog/whisper-to-parakeet-neural-engine/), [Ionio 2025 Edge STT Benchmark](https://www.ionio.ai/blog/2025-edge-speech-to-text-model-benchmark-whisper-vs-competitors), [United-MedASR](https://arxiv.org/html/2412.00055v1).

## 7. Recommendation

**Yes, commit time to this. Approximate budget: 1–2 days for MVP integration, 1 day for tuning.**

**Minimum Viable Integration:**

1. Add SwiftPM dependency: `.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.14.4")`. Apache 2.0, iOS 17+ baseline matches the project.
2. Pick **`parakeet-tdt-0.6b-v2`** as the primary model (English-only, has punctuation, best LibriSpeech-clean WER). Keep `parakeet-realtime-eou-120m-v1` in mind as a secondary endpointing aid if you want sub-400 ms partial commits.
3. Write `ParakeetTranscriptStream` (sketch above) — a peer of `SpeechRecognizer` that conforms to the existing `TranscriptStream` protocol. Wire it behind a Settings toggle so the user can A/B against Apple Speech on the same scenario fixtures.
4. Bundle the CoreML models OR add a one-time download flow. Volocal does the latter; for an air-gapped TCCC build, bundling in the IPA is cleaner — accept the +500 MB to +2.5 GB IPA size.
5. Reuse the existing 1.5 s silence-debounce + engine-priming logic — Parakeet's partial-text stream will fire the same `appendPartial` path. The current debounce works because the lower layer is opaque; nothing changes upstream.
6. Add a Settings → About row crediting Parakeet (CC-BY-4.0) and FluidAudio (Apache 2.0). Done.

**Concrete first experiment (before integrating):** Pull `FluidAudio` into a throwaway Xcode project, run `AsrManager.transcribe(_:)` on the `tests/scenarios/*.txt` audio (or a recorded read-aloud of one), and compare WER against the same `SFSpeechRecognizer` output on key medical terms. **One afternoon's work** to know whether the accuracy delta is real for your use case before touching TCCC.

**Alternatives if Parakeet underperforms in your domain:**

- **WhisperKit (Argmax)** with `large-v3-turbo` on the iPhone 17 Pro ANE. Public, mature iOS path. Slightly worse WER on clean speech (2.2% vs 1.69%) but better diversity in domain coverage from 680k hours of training. Argmax's iPhone 17 benchmark page covers it directly.
- **Speechmatics' on-device medical model** is mentioned as state-of-the-art for medical (93% real-world accuracy) but it's commercial and almost certainly not deployable inside SideStore distribution constraints.
- **Fine-tuning route:** If raw Parakeet underperforms on your specific terms, NeMo's domain-adaptation flow is well-documented. The cost is 1–2 weeks of synthetic medical data + LoRA fine-tune + reconvert to CoreML. Worth doing only after you've shipped the un-tuned version and measured what's failing.

## 8. Honest Uncertainty

- **No public iPhone 17 Pro RTFx number for Parakeet specifically.** Argmax's piece is suggestive but doesn't isolate the v2-on-A19-ANE figure. Real numbers will emerge from your own first-run profiling.
- **Battery cost of continuous ANE inference over multi-hour field sessions** is unmeasured for this stack. Plausibly better than `SFSpeechRecognizer` (which itself uses ANE for the on-device path) but unconfirmed.
- **Streaming partial-text quality of the EOU 120M variant on noisy combat audio** is untested publicly. Lab benchmarks on LibriSpeech-clean are cleaner than reality.
- **iOS 26 / Foundation Models interaction.** Your project already uses `TCCCLanguageModel` for SLM tasks. Running Parakeet (CoreML on ANE) alongside Foundation Models (which also wants ANE for token generation) may cause contention. Volocal solves this by routing Parakeet to ANE and Qwen3.5-2B to CPU+GPU. You'll likely want the same allocation discipline once SLM is doing real work in production.

These are the four numbers worth gathering on real hardware before treating this report as final.

---

**Sources**

- [nvidia/parakeet-tdt-0.6b-v2 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
- [nvidia/parakeet-tdt-0.6b-v3 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- [FluidInference/parakeet-tdt-0.6b-v2-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml)
- [FluidInference/parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- [FluidInference/parakeet-realtime-eou-120m-coreml](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml)
- [FluidAudio repo (Apache 2.0)](https://github.com/FluidInference/FluidAudio)
- [FluidAudio Benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- [FluidAudio API reference](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md)
- [Argmax — iPhone 17 on-device inference benchmarks](https://www.argmaxinc.com/blog/iphone-17-on-device-inference-benchmarks)
- [Whisper to Parakeet on Neural Engine (MacParakeet)](https://macparakeet.com/blog/whisper-to-parakeet-neural-engine/)
- [senstella/parakeet-mlx (Python reference)](https://github.com/senstella/parakeet-mlx)
- [FluidInference/swift-parakeet-mlx (archived July 2025)](https://github.com/FluidInference/swift-parakeet-mlx)
- [fikrikarim/volocal — iOS app using FluidAudio](https://github.com/fikrikarim/volocal)
- [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/)
- [CC-BY-4.0 deed](https://creativecommons.org/licenses/by/4.0/deed.en)
- [NVIDIA Parakeet-TDT blog](https://developer.nvidia.com/blog/turbocharge-asr-accuracy-and-speed-with-nvidia-nemo-parakeet-tdt/)
- [Ionio 2025 Edge STT Benchmark](https://www.ionio.ai/blog/2025-edge-speech-to-text-model-benchmark-whisper-vs-competitors)
- [United-MedASR (medical ASR with Parakeet)](https://arxiv.org/html/2412.00055v1)
