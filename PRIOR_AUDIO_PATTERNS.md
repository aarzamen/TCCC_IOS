# Prior Audio Patterns — Research for Granite Speech long-form crash

Context recap: Granite Speech 4.0 1B 5-bit primes at ~2.16 GB resident on
iPhone 17 Pro and transcribes a 14-s fixture cleanly (peak phys_footprint
2.46 GB, only +250 MB above post-load). Feeding it a 100-s fixture
(`1.6 M-sample` Float32 array) crashes the app via SIGKILL/jetsam ~3 s
into transcribe — the encoder's forward pass on the full input pushes
peak above the 6 GB cap before any token returns. Today the runtime
hands `audio: MLXArray` to `model.generateStream(...)` as a single
slab (`Packages/TCCCAudio/Sources/TCCCAudio/GraniteSpeechRuntime.swift:162-170`).
Sprint 2/3 needs to replace that single-slab call with chunked or
sliding-window encode so peak memory stays bounded for 90-min audio.

This report inventories Mike's prior repos that already hit a related
problem and surfaces the patterns most directly transferable.

## Inventory

| Repo | Relevance | One-line |
|---|---|---|
| `/Users/ama/TCCC_FEB_2026` | **HIGH** | Python prototype — has the exact `chunks(chunk_duration_sec, overlap_sec)` generator + `transcribe_chunk(audio, offset_sec)` pattern this iOS port is meant to mirror. Authoritative reference. |
| `/Users/ama/FlowScribe` | **HIGH** | Native iOS, Parakeet via FluidAudio, AVAudioEngine tap → 80 000-sample (5 s) chunk emit + force-flush ceiling at 32 000 samples. Closest iOS analogue. |
| `/Users/ama/ASR_2/FlowScribe` | duplicate | Older fork of FlowScribe, same files, no new patterns. |
| `/Users/ama/q2-edge-chat/Q2 Edge Chat` | **MED** | Native iOS, `actor AudioCaptureService` with explicit hardware→16 kHz frame-count math, `bufferSize: AVAudioFrameCount = 4096` (256 ms @ 16 kHz). |
| `/Users/ama/TCCC_IOS` (current) | self | Already has `ParakeetTranscriptStream.ringBuffer: [AVAudioPCMBuffer]` lead-in pattern with frame-counted eviction (`Audio/ParakeetTranscriptStream.swift:541-548`). Producer side is solved. |
| `/Users/ama/SimpleSwiftScribe` | none | LLM-only project, no audio code. |
| `/Users/ama/q2-edge-chat/handy_Pi` | none | React/web project, no Swift. |
| `/Users/ama/dictation-app` | none | TypeScript-only. |
| `/Users/ama/live-asr-transcription-demo` | none | TypeScript demo, no native audio. |
| `/Users/ama/TCCC` | none | No Swift audio code. |
| `/Users/ama/tccc-project` | none | No Swift audio code. |
| `/Users/ama/fluidaudio sept` | none | Just `.rtf` reference docs + the silero tar — no source. |

No prior repo had the literal name `RingBuffer` / `CircularBuffer` /
`TPCircularBuffer`, no prior `AsyncStream<...Buffer>` wrappers, and no
prior `phys_footprint` / `os_proc_available_memory` instrumentation
(that pattern is **only** present in TCCC_IOS itself, added by Sprint 1
G2 in `Packages/TCCCAudio/Sources/TCCCAudio/MemoryMonitor.swift:74-81`).

## Top patterns to lift

### 1. Python prototype's chunk-with-overlap generator (Pattern: Sliding-window encoder, lift wholesale)

- Source: `TCCC_FEB_2026/src/audio.py:115-173`, consumer at
  `TCCC_FEB_2026/src/pipeline_runner.py:139-167` and
  `TCCC_FEB_2026/src/asr.py:79-134`.
- Snippet (the generator):
  ```python
  def chunks(self, chunk_duration_sec: int = 60, overlap_sec: int = 3):
      if not (0 <= overlap_sec < chunk_duration_sec):
          raise ValueError(...)
      chunk_samples = chunk_duration_sec * self.sample_rate
      overlap_samples = overlap_sec * self.sample_rate
      step_samples = chunk_samples - overlap_samples
      total_samples = self.num_samples
      start_sample = 0
      last_end_sample = 0
      while start_sample < total_samples:
          end_sample = min(start_sample + chunk_samples, total_samples)
          if end_sample <= last_end_sample:
              start_sample += step_samples
              continue
          chunk_audio = self.audio[start_sample:end_sample]
          start_sec = start_sample / self.sample_rate
          end_sec = end_sample / self.sample_rate
          last_end_sample = end_sample
          yield AudioChunk(audio=chunk_audio, start_sec=start_sec, end_sec=end_sec)
          start_sample += step_samples
          if total_samples - start_sample < overlap_samples:
              break
  ```
- Snippet (the consumer):
  ```python
  for i, chunk in enumerate(chunks):
      result = asr_engine.transcribe_chunk(chunk.audio, offset_sec=chunk.start_sec)
      for seg in result.segments:
          all_segments.append(seg)
  ```
  Inside `transcribe_chunk`, the offset is applied at the segment
  boundary (`asr.py:131-132`): `if offset_sec > 0: return
  transcription.offset_timestamps(offset_sec)`.
- Problem solved: bounds the encoder's peak working-set memory to
  `chunk_duration_sec` of audio regardless of total file length. The
  3-s overlap exists because Whisper-class models can drop the first
  ~250 ms of speech that lands at a chunk boundary; the overlap +
  stitching at offset gives the next chunk's first segment a clean
  decode of any word that was bisected.
- Adapt for Granite Speech: this is the canonical pattern this iOS
  port is meant to reproduce — the Python prototype is "authoritative
  for state extraction + report generation" per `CLAUDE.md`. The
  Granite Speech encoder runs at 16 kHz mono Float32 with block-wise
  attention `context_size=200` and 5× downsample, so a 30-s chunk =
  480 000 samples → 1875 mel frames → ~375 encoder frames. That is
  comfortably below the regime that crashed at 100 s. Ship a
  `GraniteSpeechRuntime.transcribeChunked(audioURL:, chunkDurationSec:
  Int = 30, overlapSec: Int = 3)` method that loads the full
  `MLXArray` once via `loadAudioArray(from: sampleRate: 16_000)`,
  iterates `MLXArray` slices, calls `model.generateStream` per slice,
  and stitches by ignoring tokens whose audio offset falls inside the
  previous chunk's last `overlap_sec`. Open question: does
  `MLXArray` slice share storage with the parent (zero-copy) or copy?
  If it shares, free the parent only at the end; if it copies, free
  both parent and slice eagerly between iterations.

### 2. FlowScribe's "emit when buffer ≥ N samples, drop the head" producer (Pattern: Bounded streaming buffer, for live mic capture)

- Source: `FlowScribe/FlowScribe/AudioManager.swift:100-135`. Buffer
  state at lines 15-16. Tap install at lines 49-73.
- Snippet:
  ```swift
  private var audioBuffer = [Float]()
  private let bufferSize = 512   // tap fragment size
  // ...
  inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: inputFormat) {
      [weak self] buffer, _ in self?.processAudioBuffer(buffer)
  }
  // ...
  private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
      // ... resample to 16 kHz if needed ...
      audioBuffer.append(contentsOf: rawSamples)
      // Increased buffer to 80000 samples (5 seconds at 16kHz)
      if audioBuffer.count >= 80000 {
          audioDataCallback?(Array(audioBuffer.prefix(80000)))
          audioBuffer.removeFirst(80000)
      }
  }
  ```
  Plus the consumer side at
  `FlowScribe/FlowScribe/TranscriptionManager.swift:374-380`:
  ```swift
  // Force transcription if buffer gets too large (2 seconds at 16kHz)
  if speechBuffer.count > 32000 {
      await transcribeBuffer(endTime: currentTime)
  }
  ```
- Problem solved: producer (audio render thread) emits a
  fixed-duration window every 5 s without unbounded growth, AND a
  separate hard ceiling (`speechBuffer > 32000` = 2 s) force-flushes
  the consumer if VAD never fires an end-of-utterance — the same
  defense the current TCCC `ParakeetTranscriptStream` uses for
  `partialStringCeiling = 8000` (`TCCC_IOS/Audio/ParakeetTranscriptStream.swift:139`).
- Adapt for Granite Speech: irrelevant for the *file-mode* G2 crash
  (the audio is already in memory before transcribe begins) — but
  becomes the foundation when G3 ships live mic. Pair this with
  pattern 1: the live mic accumulates into a `[Float]` (or `MLXArray`
  slab); every `chunkDurationSec - overlapSec` seconds, slice the
  trailing `chunkDurationSec` worth of samples, hand that slice to
  Granite, and `removeFirst(stepSeconds * 16000)` to drop the head.
  The `removeFirst(80000)` line is the literal pattern. **Don't** copy
  FlowScribe's `[Float].removeFirst(N)` mechanically — Swift's
  `Array.removeFirst(_:)` is O(N) memcpy of remaining elements; over a
  90-min recording with chunk emits every ~30 s, that's fine, but if
  emit cadence drops below ~1 s, switch to a head-index ring or
  `Deque` (Swift Collections).

### 3. Q2 Edge Chat's hardware→target frame-count math (Pattern: Format-converter sizing)

- Source: `q2-edge-chat/Q2 Edge Chat/Services/Audio/AudioCaptureService.swift:25-79, 102-134`.
- Snippet:
  ```swift
  /// Buffer size: 4096 samples = 256ms at 16kHz (matches Silero VAD chunk size)
  private let bufferSize: AVAudioFrameCount = 4096

  let hardwareFormat = inputNode.outputFormat(forBus: 0)
  guard let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate,
      channels: targetChannels, interleaved: false
  ) else { throw AudioCaptureError.formatCreationFailed }
  guard let audioConverter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
      throw AudioCaptureError.converterCreationFailed
  }
  // Calculate buffer size for hardware sample rate
  let hardwareBufferSize = AVAudioFrameCount(
      Double(bufferSize) * hardwareFormat.sampleRate / targetSampleRate
  )
  inputNode.installTap(onBus: 0, bufferSize: hardwareBufferSize, format: hardwareFormat) {
      [weak self] buffer, _ in
      Task.detached(priority: .userInitiated) {
          await self.processAndPublish(buffer: buffer, converter: audioConverter, targetFormat: targetFormat)
      }
  }
  // ...
  private func processAndPublish(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
      let ratio = targetFormat.sampleRate / buffer.format.sampleRate
      let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
      guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }
      // ... convert ...
  }
  ```
- Problem solved: the hardware tap rate is the *device's* native rate
  (44.1 / 48 / 24 kHz on iPhone), not 16 kHz. If you ask for a tap
  bufferSize in target units, you'll fragment buffers at the wrong
  cadence. The math `hardwareBufferSize = targetSamples × hardware /
  target` makes "I want a tap fragment of 256 ms regardless of mic
  rate" actually true. The output buffer's `frameCapacity` is
  computed the same way in reverse.
- Adapt for Granite Speech: this is the right shape for the chunk
  *boundary alignment* problem in pattern 1. For file mode (the G2
  crash), `loadAudioArray(from:, sampleRate: 16_000)` already does the
  resample, so chunk boundaries are aligned to 16 kHz frames trivially
  (e.g. 30 s = 480 000 samples). For live mic (G3), use this math
  directly when sizing the tap so you don't end up emitting partial
  hardware buffers across chunk boundaries. Note: the existing
  `ParakeetTranscriptStream` already does the equivalent in its
  `resampleToTarget(...)` (`TCCC_IOS/Audio/ParakeetTranscriptStream.swift:320-349`)
  with `ratio = targetSampleRate / converter.inputFormat.sampleRate`
  and `outFrameCapacity = ceil(input.frameLength * ratio) + 16`. The
  Q2 reference is cleaner standalone code if a reviewer wants to see
  the math in isolation.

## Anti-patterns

- **FlowScribe stores the entire recording for post-hoc diarization.**
  `FlowScribe/FlowScribe/TranscriptionManager.swift:90-91`:
  `private var fullAudioBuffer = [Float]()  // Complete recording for diarization`,
  appended every chunk at line 250 and only freed at end-of-recording
  (line 680). Over a 90-min mono 16 kHz Float32 stream that's
  86 400 000 samples × 4 bytes = **345 MB** of resident array. That
  alone is a significant fraction of the 6 GB cap and is exactly the
  kind of footprint Granite Speech can't afford during transcribe.
  Don't replicate. If diarization or post-hoc operations are needed
  later, write to disk via the existing `AVAudioFile` path
  (`ParakeetTranscriptStream.swift:558` already does this for AAC m4a)
  and re-read on demand — disk-backed, NSFileProtectionComplete, and
  bounded.

- **FlowScribe's pre-roll uses an array-of-arrays.**
  `FlowScribe/FlowScribe/TranscriptionManager.swift:234-235`:
  `private var preRollBuffer: [[Float]] = []`. With `preRollChunks =
  3` and 512-sample chunks it's tiny (~6 kB) so it's fine *here*, but
  any larger pre-roll under this layout pays double allocation and
  cache-miss costs vs. a single flat `[Float]` with a head-index. For
  Granite Speech's chunk-overlap region (3 s × 16 kHz × 4 = 48 kB
  per overlap) the difference doesn't matter — but if the eventual
  design uses larger pre-roll for warm-context, switch to a flat
  buffer.

- **Single-shot `model.generateStream(audio: fullArray, ...)`** —
  the current TCCC pattern at
  `Packages/TCCCAudio/Sources/TCCCAudio/GraniteSpeechRuntime.swift:164-170`.
  This is the bug under investigation; calling it out explicitly so
  the chunked replacement isn't accidentally bypassed by a future
  caller. The TCCCAudio public API should *only* expose chunked
  paths once Sprint 2/3 lands; the current single-slab signature
  should be marked internal or deprecated.

## Open questions

1. **Does `MLXArray` slicing share storage or copy?** The lift of
   pattern 1 hinges on this. If `audio[start..<end]` is a view, we
   can iterate without freeing the parent slab (saves the load-time
   re-decode). If it copies, peak memory during chunk transition =
   parent + new slice + previous slice's encoder activations, which
   could itself be the OOM. Suggested test: prime the model on
   simulator, slice a 1.6 M-sample `MLXArray` into 30-s windows in a
   loop, log `phys_footprint` per iteration. Reference path:
   `Packages/TCCCAudio/Sources/TCCCAudio/MemoryMonitor.swift:74-81`.

2. **Does `model.generateStream(...)` retain encoder state across
   calls, or recompute mel-spectrogram + encoder from scratch each
   chunk?** If it recomputes, chunk overlap means we pay the encoder
   cost once per chunk × overlap-fraction redundantly (10% extra at
   3 s overlap / 30 s chunk). Tolerable. If it retains state, naive
   per-chunk calls will accumulate KV-cache forever — same OOM
   path, different cause. The mlx-audio-swift `GraniteSpeechModel`
   API doc at `Packages/TCCCAudio/CLAUDE.md` ("Loader API surface at
   the pinned SHA") doesn't cover the encoder lifecycle; need to
   read `MLXAudioSTT/GraniteSpeechModel.swift` upstream.

3. **What's the right chunk size?** The Python prototype uses 60 s
   (with mlx-whisper, which has 30 s native context). Granite Speech
   has `context_size=200` block-wise attention with 5× downsample,
   so 200 encoder frames ≈ 200 × 5 × 10 ms (CTC stride) = 10 s of
   audio per attention block — meaning the model already chunks
   internally at 10 s and the extra-large input is just running the
   mel + encoder forward pass on too much audio at once. A 30-s
   external chunk = 3 internal blocks should match the model's
   native rhythm. But this needs validation: 30 s, 60 s, 90 s on
   the same fixture, log peak phys_footprint and recall delta. The
   crash threshold on iPhone 17 Pro is *somewhere between 14 s and
   100 s* per Sprint 1 G2's results — bisecting that gives the
   actual safe ceiling without overlap.

4. **Does the FlowScribe 5-s emit cadence make sense as a *live*
   chunk size for Granite Speech?** It's tuned for streaming Parakeet
   (RNN-T, sub-second latency target). Granite Speech's
   `transcribe(14 s) = 5.78 s` is 2.4× real-time, so a 5 s live
   chunk would queue forever. Need a separate live-mode policy:
   either accept >5 s end-of-utterance latency, or run Granite
   Speech only in batch mode and keep Parakeet as the live path.
   This is a Sprint 3 scope question, not Sprint 2.

5. **Does the resolver cache model weights across `unload() →
   prime()`?** Sprint 1 G2's data
   (`Packages/TCCCAudio/CLAUDE.md` "Warm-run prime time: 1.04 s
   (Δ +49 MB only)") suggests yes — the page cache survives. If
   chunked encode needs to *unload* between chunks to reclaim
   working-set memory (extreme case), that warm-prime cost is
   bearable. Probably overkill, but it's an out if peak memory still
   busts the cap with chunking alone.
