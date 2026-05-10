# Sprint 2 Audio Ingestion Comparison

**Date:** 2026-05-10

**Repo:** `/Users/ama/.codex/worktrees/f864/TCCC_IOS`

**Audience:** Sprint 2 planning session for the TCCC.ai iOS Granite Speech path.

**Status:** source-backed research document with explicit physical-measurement blockers.

**Tag status:** do not tag `sprint-2-research-complete` from this document alone. The
three strategy runs requested in the prompt still need to be executed on the physical
iPhone 17 Pro after a chunking harness is added.

**Why this document is still useful:** two of the uncertain questions were answerable
from pinned source, and one of the prompt assumptions is wrong in a load-bearing way:
Granite's `context_size=200` is about four seconds of encoder frames in the current
`mlx-audio-swift` implementation, not about ten seconds of raw audio.

---
## 1. Executive Summary

The Sprint 2 implementation should start with bounded, independent Granite Speech
transcription windows fed from a back-pressured capture pipeline. In the terms of the
prompt, that is closest to Strategy A, but with a correction: the model's native
encoder attention block is not ten seconds. Source inspection of pinned
`mlx-audio-swift` shows 16 kHz audio is converted to mel frames with a 160-sample hop
and then pair-stacked, producing about 50 encoder frames per second. A
`context_size=200` encoder block is therefore about four seconds of raw audio.

That correction changes the decision. A literal 10-second window is not a single native
encoder block; it is roughly two and a half block-wise attention blocks plus projector
padding. It may still be the right product choice because it amortizes warm-start cost
and reduces boundary stitching, but it must be treated as an engineering window, not as
the architecture's exact boundary.

Strategy B, 3-4 second independent chunks, is now more plausible technically than the
original prompt implied because it lands near one encoder attention block. It is still
not my recommendation for the main Sprint 2 path because Sprint 1 measured warm prime at
1.04 seconds. Spending about one second of overhead on every 3-4 second slice is too
expensive unless the app needs a low-latency preview lane separate from the durable
encounter transcript.

Strategy C, 15-30 second windows, should be used as a ceiling-finding experiment, not as
the initial production architecture. Source shows `generateStream(audio:)` extracts
features for the whole supplied audio array, runs the Conformer over the whole feature
sequence, creates a fresh decoder KV cache, and clears MLX cache only at the end of the
call. Block-wise attention bounds the attention matrix per block, but it does not make
the full encoder pass stream statefully. The G2 jetsam on about 100 seconds of audio is
consistent with full-input activations still scaling with input length.

The capture-side fix is not optional. The current live path installs an
`AVAudioEngine` tap with `bufferSize: 1024` and spawns a new `Task` carrying a copied
buffer for every tap callback. Sprint 1 measured that mailbox path growing from about
2.16 GB after model load to about 4.46 GB within roughly 30 seconds of live capture.
Whatever transcription window wins, Sprint 2 needs one bounded capture owner, one
bounded writer/segmenter, explicit overflow counters, and a single serialized Granite
worker.

My recommendation for the Sprint 2 spec writer is:
1. Build the capture pipeline first: exact 16 kHz mono windowing, bounded ring buffer,
   no per-callback unstructured task fan-out, raw audio separate from UI gain.
2. Implement Granite transcription as independent chunks with one to two seconds of
   overlap and deterministic boundary stitching.
3. Run the physical-device window sweep in this order: 4 s, 8 s, 10 s, 15 s, 20 s,
   30 s. Stop increasing as soon as peak `phys_footprint` trends above the 75% warning
   band or the profile stops returning to baseline after `Memory.clearCache()`.
4. Use 8-10 seconds only if it stays stable in the five-minute run; otherwise use
   4-second windows as the architecture-aligned fallback.
5. Keep 3-4 second chunks as a possible low-latency preview lane, not the durable
   transcript path, unless keyword recall and boundary continuity beat expectations.

This document does not contain the median/p95 latency and five-minute
`phys_footprint` curves requested for final Sprint 2 sign-off. Those require an
instrumented physical-device run. The absence is marked as `BLOCKED:` in the strategy
sections and is the reason this commit should remain untagged.

---
## 2. Method

This pass used four kinds of evidence.

First, I read the three Sprint 1 resumption documents in the required order:
`SPRINT_1_ACCEPTANCE.md`, `Packages/TCCCAudio/CLAUDE.md`, and
`PRIOR_AUDIO_PATTERNS.md`.

Second, I inspected the current production code that owns Granite transcription and
live capture:
- `Packages/TCCCAudio/Sources/TCCCAudio/GraniteSpeechRuntime.swift`
- `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift`
- `Packages/TCCCAudio/Sources/TCCCAudio/MemoryMonitor.swift`
- `TCCC_IOS/DevTools/GraniteBakeoffView.swift`

Third, I resolved the pinned `Packages/TCCCAudio` Swift package and read the exact
`mlx-audio-swift` and `mlx-swift` source used by this repo:
- `mlx-audio-swift` revision `fcbd04daa1bfebe881932f630af2ba6ce9af3274`
- `mlx-swift` resolved at `0.31.3`
- `mlx-swift-lm` resolved at `2.31.3`

Fourth, I delegated read-only prior-art audits across Mike's older audio projects and
synthesized the useful patterns. Those audits stayed read-only and treated prior repos
as design memory, not copy-paste sources.
### 2.1 Sprint 1 Empirical Baseline

The strongest measured evidence remains Sprint 1's physical iPhone 17 Pro runs.
| Observation | Sprint 1 value | Source |
| --- | ---: | --- |
| Validation device | iPhone 17 Pro, iOS 26.2, UDID `00008150-0018046C0188401C` | `SPRINT_1_ACCEPTANCE.md` |
| Cold Granite prime | 1.99 s | `SPRINT_1_ACCEPTANCE.md` |
| Cold-prime footprint delta | +2196.3 MB | `SPRINT_1_ACCEPTANCE.md` |
| Post-load resident | 2.16 GB | `SPRINT_1_ACCEPTANCE.md` |
| Available after model load | 3.84 GB | `SPRINT_1_ACCEPTANCE.md` |
| Effective runtime cap | about 6.0 GB | `SPRINT_1_ACCEPTANCE.md` |
| 14 s file transcribe time | 5.78 s | `SPRINT_1_ACCEPTANCE.md` |
| 14 s decode speed | about 2.4 audio-seconds per wall-second | `SPRINT_1_ACCEPTANCE.md` |
| 14 s peak `phys_footprint` | 2.46 GB | `SPRINT_1_ACCEPTANCE.md` |
| Warm reprime | 1.04 s, +49 MB | `SPRINT_1_ACCEPTANCE.md` |
| Long fixture failure | about 100 s fixture jetsam-killed about 3 s into transcribe | `SPRINT_1_ACCEPTANCE.md` |
| Live capture failure | `phys_footprint` 2.16 GB to 4.46 GB in about 30 s, then jetsam | `SPRINT_1_ACCEPTANCE.md` |

These numbers are not a substitute for the Strategy A/B/C sweep. They do establish
that Granite itself can run under the 6 GB entitlement cap for short audio, and that
both known failures are length/back-pressure failures rather than basic model-loading
failures.
### 2.2 Current Code Path Inspected

`GraniteSpeechRuntime.transcribe(audioURL:)` currently loads the whole audio file into
one MLX array at 16 kHz and passes it to `model.generateStream(audio:)`.

The relevant shape is:

```swift
let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)
return model.generateStream(audio: audio, ...)
```

That is a whole-file API boundary. It does not stream raw PCM into the encoder.

`GraniteSpeechTranscriptStream` currently records audio to a file and then transcribes
the whole recording after stop. Its tap callback:
- uses `installTap(onBus: 0, bufferSize: 1024, format: format)`;
- copies the incoming buffer;
- applies UI gain to the copy;
- sends a level update;
- spawns `Task { await self?.ingestBuffer(copy) }`.

This is exactly the mailbox-growth pattern Sprint 1 identified.

`MemoryMonitor` is the right package-local source for jetsam-relevant measurements. It
uses `task_vm_info.phys_footprint` and documents that `resident_size` is not the
decision metric.
### 2.3 Upstream Granite Source Inspected

The source inspection matters because the open questions are mostly about what the
Granite API actually preserves between calls.

The pinned Granite implementation performs this sequence inside `generateStream`:
1. `extractFeatures(audio)`
2. `getAudioFeatures(inputFeatures)`
3. `buildPrompt(numAudioTokens:userPrompt:)`
4. `buildInputEmbeds(promptIds:audioFeatures:)`
5. `makeCache()`
6. `languageModel(cache:cache,inputEmbeddings:)`
7. token loop
8. `Memory.clearCache()`

The cache is created inside the call. There is no argument or return value for encoder
state, audio features, or decoder KV-cache continuation.

The encoder attention code pads to `contextSize`, computes `numBlocks`, projects `q`,
`k`, and `v` across the padded sequence, reshapes into blocks, and performs attention
within each block. That bounds the attention block, but it does not turn a 100-second
audio array into a streaming encoder.
### 2.4 Fixture Plan

The final physical benchmark should generate a TCCC-vocabulary fixture family from the
same v1 Section 6 narrative used by Sprint 1. The important point is that the audio must
contain the tokens that matter to TCCC extraction, not generic dictation prose.

Recommended fixture set:
- 14 s: current known-good first paragraph baseline.
- 30 s: short long-form sanity check.
- 60 s: first real field-note stressor.
- 100 s: reproduces Sprint 1 failure.
- 300 s: target five-minute acceptance fixture.

Recommended generation path on macOS:

```bash
cd /Users/ama/.codex/worktrees/f864/TCCC_IOS
mkdir -p .tmp/audio-fixtures
say -v Alex -o .tmp/audio-fixtures/section6-raw.aiff "$(cat TCCC_IOS/Resources/test_5min.txt)"
afconvert -f WAVE -d LEF32@16000 -c 1 .tmp/audio-fixtures/section6-raw.aiff .tmp/audio-fixtures/section6-16k.wav
```

That command is a fixture-generation starting point, not a guarantee of final duration.
The benchmark harness should explicitly trim or repeat narrative spans to create the
target lengths.
### 2.5 Device Method Needed For Completion

The requested median/p95 latency, five-minute footprint profile, keyword recall, and
boundary continuity require the physical iPhone. Simulator is not acceptable because MLX
on iOS simulator is not the same runtime path and may not run the required Metal
workload.

The device run should:
- use the existing model resolver and bookmark store;
- avoid hidden downloads;
- use `MemoryMonitorCSVLogger`;
- record `Memory.reading()` or `Memory.snapshot()` around every chunk;
- record `STTGenerationInfo.tokensPerSecond`;
- record first-token time, final-result time, and chunk-complete time;
- write one JSONL or CSV row per chunk;
- preserve exact chunk boundary timestamps and overlap spans;
- compute keyword recall on the transcribed portion actually attempted.
### 2.6 What I Did Not Measure Here

I did not run the A/B/C strategy sweep on the physical iPhone in this session.

I attempted a local macOS SwiftPM MLX slice probe in a temporary directory to test
slice memory directly. The probe built, but execution failed because the standalone
SwiftPM executable could not load MLX's default Metal library:

`MLX error: Failed to load the default metallib. library not found`

That means the slice answer below is source-backed, not device-measured.
BLOCKED: physical-device benchmark harness and runs are still required before this
research can be called complete.

---
## 3. Strategy A Results: Moderate Independent Windows
### 3.1 Strategy Definition

The prompt describes Strategy A as encoded chunking at a moderate window of about ten
seconds, with each window passed through the Granite Speech encoder in a full
transcribe call.

I would restate it for this codebase:

Strategy A is independent `generateStream(audio:)` calls over bounded audio windows,
fed by a stable capture segmenter, with overlap-based transcript stitching.

The important correction is that ten seconds is not the encoder's native
`context_size=200` boundary in this implementation. Ten seconds is an engineering
latency/quality tradeoff window.
### 3.2 Source Evidence

The upstream feature path uses:
- sample rate: 16,000 Hz;
- STFT hop: 160 samples;
- mel frame rate: 100 frames/s;
- pair-stacked encoder frames: about 50 frames/s;
- encoder context size: 200 frames;
- derived context duration: about 4 seconds.

Therefore:
| Window | Approx encoder frames | Approx context blocks |
| ---: | ---: | ---: |
| 4 s | 200 | 1.0 |
| 8 s | 400 | 2.0 |
| 10 s | 500 | 2.5 |
| 15 s | 750 | 3.75 |
| 20 s | 1000 | 5.0 |
| 30 s | 1500 | 7.5 |

This table is why I do not want the Sprint 2 spec to assert that ten seconds is a
native model boundary.
### 3.3 Wall-Clock Latency
Measured in this session: not measured.

Relevant Sprint 1 baseline:
- 14 s fixture completed in 5.78 s, about 2.4 audio-seconds per wall-second.
- Warm reprime measured 1.04 s.
Expected Strategy A latency:
- first transcript display latency is approximately window length plus transcribe time;
- for a 10 s window, the operator sees durable text on the order of 10-15 s after the
  first spoken words;
- for an 8 s window, first display likely lands closer to 8-12 s;
- overlap and stitching add small CPU cost but should be minor compared with Granite.
BLOCKED: median and p95 mic-input-to-display latency need physical-device runs.
### 3.4 Peak `phys_footprint`
Measured in this session: not measured.

Relevant Sprint 1 baseline:
- post-load footprint/resident area was about 2.16 GB resident;
- 14 s single-shot peak `phys_footprint` was 2.46 GB;
- about 100 s single-shot jetsam-killed the app.
Expected Strategy A profile:
- stable or sawtooth if each chunk frees intermediate tensors and `Memory.clearCache()`
  works as intended;
- growing-then-stable if MLX cache reuses same-size buffers after the first few chunks;
- unsafe if each chunk size creates new cached buffers and cache limit is not bounded.

Strategy A's main memory advantage is not magic encoder state. It is simply not asking
Granite to encode the entire encounter in one call.
BLOCKED: five-minute steady-state capture+transcribe profile needs device CSV.
### 3.5 Tokens/Sec Throughput
Measured in this session: not measured.

The upstream `generateStream` emits `STTGenerationInfo.tokensPerSecond` after each call.
The Sprint 2 harness should persist that value per chunk.
Expected shape:
- 8-10 s chunks should amortize fixed prefill better than 3-4 s chunks;
- token/s may look deceptively healthy even if first-token latency is poor;
- report both token/s and wall-clock chunk completion.
BLOCKED: device strategy rows needed.
### 3.6 Keyword Recall
Measured in this session: not measured.

Strategy A should be evaluated against the v1 Section 6 token list already visible in
`GraniteBakeoffView`. The recall denominator must be restricted to the fixture portion
actually transcribed.
Expected behavior:
- ten-ish second windows may preserve enough local context for TCCC phrases;
- one to two seconds of overlap should recover most word cuts;
- deterministic dedupe is needed so overlapped drugs and vitals are not double-applied
  into the encounter ledger.
BLOCKED: recall requires physical transcriptions.
### 3.7 Boundary Continuity
Measured in this session: not measured.
Expected continuity risk:
- a phrase such as "needle decompression" can split across windows;
- medication plus dose can split across windows;
- call sign or grid digits can be duplicated or dropped at overlap boundaries.

Recommended annotation in the benchmark output:
- print the last 15 words of chunk N;
- print the first 15 words of chunk N+1;
- print the stitched span;
- mark whether the overlap deduper kept, dropped, or merged each repeated phrase.
BLOCKED: transcript samples need the chunking harness.
### 3.8 Encoder Warmup Amortization
Measured in this session: not measured.

Sprint 1 warm reprime was 1.04 seconds. That number is a useful warning but not the same
as per-chunk overhead inside a primed runtime. The per-chunk overhead for Strategy A
must be measured as:

`prefillTime + featureExtractionTime + encoderTime`

The upstream info object reports `prefillTime`, but it does not separately expose
feature extraction and encoder time. The benchmark should add signposts around
`extractFeatures`, `getAudioFeatures`, prompt build, prefill, and token loop if the
research harness patches upstream locally or wraps a forked helper.
Expected amortization:
- much better than Strategy B;
- much worse than true stateful streaming, which Granite does not currently expose.
### 3.9 MLX Allocation Pattern
Measured in this session: source-inspected, not device-measured.

`generateStream` calls `Memory.clearCache()` at the end. That should reduce cache
growth, but MLX documentation says buffers can remain cached until limit behavior is
enforced, and that iOS developers should tune `Memory.cacheLimit` for jetsam-sensitive
workloads.

Strategy A should set and sweep `Memory.cacheLimit` in the benchmark. A safe starting
point is not to assume the default cache policy is acceptable on iPhone.

---
## 4. Strategy B Results: 3-4 Second Independent Slices
### 4.1 Strategy Definition

Strategy B feeds the model short independent audio slices, about 3-4 seconds each.

In this codebase, that still means every slice runs feature extraction, the Granite
encoder, the projector, decoder prefill, and token generation. There is no public API
for "raw PCM into shared encoder state" in the pinned Granite implementation.
### 4.2 Why Strategy B Looks Better After Source Inspection

The prompt framed 3-4 second chunks as "non-encoded short chunks" and treated ten
seconds as the model's native context size.

The source says otherwise:
- 4 seconds is approximately one `context_size=200` attention block;
- 3 seconds is about 150 encoder frames;
- 4 seconds is about 200 encoder frames.

So Strategy B is not a weird sub-context fragment. It is close to the actual encoder
attention context duration.
### 4.3 Wall-Clock Latency
Measured in this session: not measured.
Expected behavior:
- first durable text can appear after about 3-4 seconds plus inference time;
- if inference is faster than real time, perceived latency may be tolerable;
- if fixed overhead dominates, the worker can fall behind sustained speech.

The key metric is not one isolated 4 s chunk. The metric is whether a five-minute stream
keeps queue depth bounded while the operator keeps talking.
BLOCKED: median/p95 latency and queue depth need device runs.
### 4.4 Peak `phys_footprint`
Measured in this session: not measured.
Expected memory profile:
- best per-call activation bound among A/B/C;
- more total calls, more opportunities for cache fragmentation;
- possible stable sawtooth if cache limit is configured;
- possible monotonic growth if same-size repeated calls still accumulate retained
  buffers or if capture queues are not bounded.

Strategy B will not rescue a bad capture pipeline. If tap callbacks keep spawning tasks,
3-second chunking only moves the bottleneck.
BLOCKED: five-minute profile needed.
### 4.5 Tokens/Sec Throughput
Measured in this session: not measured.
Expected behavior:
- token/s may be lower than Strategy A because prefill/setup happens more often;
- warm-start effects may hide the cost in short tests;
- a sustained five-minute run is required.

The Sprint 1 warm reprime of 1.04 s is the warning sign. If a 3 s slice spends around
one second on fixed overhead, roughly a quarter to a third of the budget is overhead
before useful decode is considered.
### 4.6 Keyword Recall
Measured in this session: not measured.
Expected risk:
- 3-4 s windows may split many TCCC facts;
- overlap can help, but overlap consumes a larger fraction of each slice;
- too much overlap can duplicate facts and inflate downstream extraction events.

Strategy B needs a stronger boundary ledger than A because boundaries occur more often.
### 4.7 Boundary Continuity
Measured in this session: not measured.
Expected continuity:
- higher risk of clipped clauses;
- higher risk of repeated partial words;
- better recovery if each chunk is short enough that the model does not drift.

The benchmark should compare 3 s, 4 s, and 4 s with 1 s overlap. It should not report
"Strategy B" as one number.
### 4.8 Encoder Warmup Amortization
Measured in this session: not measured.

This is the central downside.

The correct calculation is:

`overheadPercent = fixedPerChunkTime / totalChunkWallTime`

If the chunk is 4 s of speech and the model takes 1.6 s wall time, then fixed overhead
is tolerable only if most of that 1.6 s is useful compute. If the chunk takes 3-5 s wall
time, the worker falls behind.
### 4.9 MLX Allocation Pattern
Measured in this session: source-inspected, not device-measured.

Each call creates a fresh decoder KV cache. Each call also extracts features and
computes audio features from scratch. There is no retained encoder state across calls.

Strategy B therefore buys memory by making every call small, not by making calls
incremental.

---
## 5. Strategy C Results: 15-30 Second Independent Windows
### 5.1 Strategy Definition

Strategy C tests longer independent windows: 15 s, 20 s, 30 s, and possibly beyond.

Its purpose is to find the largest stable window under the physical iPhone cap, not to
prove that long windows are inherently architecturally safe.
### 5.2 Source Evidence

Granite block-wise attention means attention matrices are bounded per `contextSize`
block. That is good.

But the implementation still:
- creates features for the full input audio;
- computes encoder layers across the full feature sequence;
- projects full `q`, `k`, and `v` over the padded sequence before reshaping into
  blocks;
- builds audio features for the whole supplied array;
- creates fresh decoder cache each call;
- clears memory cache after the call, not during the encoder pass.

This matches the Sprint 1 observation that the about 100-second input dies during the
encoder forward pass before long-form decoding can matter.
### 5.3 Wall-Clock Latency
Measured in this session: not measured.
Expected behavior:
- 15 s window: first durable text likely too slow for live extraction but maybe
  acceptable for record-and-review.
- 20 s window: likely starts to feel batchy.
- 30 s window: likely unacceptable as the only live display path, even if memory fits.

Strategy C may still be valuable for post-encounter re-transcription or high-quality
repair after a lower-latency preview lane.
BLOCKED: device runs needed.
### 5.4 Peak `phys_footprint`
Measured in this session: not measured.
Expected memory profile:
- each larger window increases full-input feature and activation memory;
- cache reuse may help after the first same-size call;
- memory may become a staircase if window sizes vary;
- jetsam may occur before the harness can emit a final info event.

The safe way to run Strategy C is a bisect with hard stop rules:
- run 15 s first;
- inspect peak and post-call return-to-baseline;
- run 20 s only if 15 s is stable;
- run 30 s only if 20 s is stable;
- stop if footprint exceeds warning threshold or if post-call cache does not settle.
BLOCKED: no Strategy C sweep was run here.
### 5.5 Tokens/Sec Throughput
Measured in this session: not measured.
Expected behavior:
- if memory fits, longer windows should amortize fixed setup better;
- token/s alone may look better while operator latency gets worse;
- the benchmark should report both generation token/s and audio-seconds/wall-second.
### 5.6 Keyword Recall
Measured in this session: not measured.
Expected behavior:
- best chance of preserving long clauses and phrase context;
- lower boundary count;
- possible degradation if long audio causes memory pressure or incomplete output.

If Strategy C can complete the full five-minute fixture through 30-second windows, it
may produce the best durable transcript. That is plausible enough to test, but not
plausible enough to assume.
### 5.7 Boundary Continuity
Measured in this session: not measured.
Expected behavior:
- fewer boundaries than A/B;
- fewer stitch points;
- larger loss if a chunk fails.

Boundary stitching remains necessary because every call is independent.
### 5.8 Encoder Warmup Amortization
Measured in this session: not measured.
Expected behavior:
- best amortization among the independent-window strategies;
- worst first-display latency;
- risk that memory headroom disappears before amortization matters.
### 5.9 MLX Allocation Pattern
Measured in this session: source-inspected, not device-measured.

The source does not show stateful encoder reuse. Strategy C is therefore not "long
stateful streaming." It is "bigger independent batches."

That is the right mental model for Sprint 2 planning.

---
## 6. Open-Question Answers
### 6.1 Does `MLXArray` Slicing Copy Or View?

Short answer: source inspection says slicing is a lazy graph operation referencing the
parent array, not an eager deep copy at subscript time. That does not mean it is free for
the Sprint 2 design.

In `MLXArray+Indexing.swift`, range subscripts call `mlx_slice`.

In MLX C++ `ops.cpp`, `slice` returns the original array if the slice is the full shape.
Otherwise it constructs a new `array` primitive with the original array as input:

```cpp
return array(
    out_shape,
    a.dtype(),
    std::make_shared<Slice>(...),
    {a});
```

That means:
- the slice is not an eager copy in the simple source-level sense;
- the slice references the parent graph input;
- evaluating downstream operations can allocate output buffers;
- holding slices of a long parent can keep the long parent alive;
- negative stride/as-strided paths may force contiguity differently.
Design implication:

Do not implement sliding windows by loading a 100-second MLX array and slicing it into
chunk arrays while expecting memory to drop. That can retain the full parent audio
array, and it still risks evaluated slice outputs. Build chunk arrays from a bounded
PCM ring or read bounded spans from disk so the long parent never exists in MLX memory.
Measurement status:
BLOCKED: the iPhone MLX memory probe still needs to measure `Memory.snapshot()` before
slice, after slice, after `eval(slice)`, after parent release, and after
`Memory.clearCache()`. A macOS temporary probe failed because the standalone SwiftPM
binary could not load MLX's default Metal library.
### 6.2 Does `model.generateStream(audio:)` Retain Encoder State Across Calls?

Short answer: no, not through the public Granite implementation pinned in this repo.
Source evidence:
- `generateStream` calls `extractFeatures(audio)` for the supplied audio each time.
- It calls `getAudioFeatures(inputFeatures)` each time.
- It calls `makeCache()` inside the function.
- `makeCache()` returns fresh `KVCacheSimple()` objects.
- There is no parameter for previous encoder state.
- There is no returned encoder state.
- There is no returned decoder KV cache.
- `Memory.clearCache()` is called near the end of the generation.

Any faster second call is therefore warm runtime behavior: weights, file cache, Metal
pipeline/cache reuse, or MLX buffer reuse. It is not a semantic continuation of the
previous audio chunk.
Design implication:

Chunk stitching must happen above Granite. Sprint 2 should not plan around hidden
encoder continuity. It should treat every chunk transcript as independent evidence and
merge the text/facts deterministically.
Measurement status:

Source answer is strong enough for architecture planning. A physical timing test is
still useful to quantify warm overhead, but it will not prove semantic state retention
unless the API changes.
### 6.3 What Is The Audio Downsampling Ratio?

Short answer: about 50 encoder frames per second from raw 16 kHz mono audio; therefore
`context_size=200` is about 4 seconds.

Source path:
- `sampleRate = 16000`
- `hopLength = 160`
- mel frame rate = 16,000 / 160 = 100 frames/s
- if mel frame count is odd, one frame is dropped
- `logmel.reshaped(-1, 2 * nMels)` pair-stacks frames
- encoder frame rate = 100 / 2 = 50 frames/s
- `context_size=200`
- context duration = 200 / 50 = 4 seconds

The model config also has:
- `windowSize = 15`
- `downsampleRate = 5`
- `numAudioTokens = ceil(encoderLength / 15) * (15 / 5)`

So one projector window is about 15 / 50 = 0.3 seconds of raw audio, and each projector
window yields 3 audio tokens.
Design implication:

The Sprint 2 spec should remove or correct the old "context_size=200 ≈ 10 s" note in
`Packages/TCCCAudio/CLAUDE.md`. The attention block is about 4 s. Ten-second windows may
still be selected, but they should be selected because the physical sweep says they are
stable and better for recall/latency, not because they are the native context size.
### 6.4 Does The Encoder Long-Form Crash Mean Block-Wise Attention Is Broken?

Not necessarily.

The source does show block-wise attention. The crash can still happen because:
- feature extraction scales with full input length;
- q/k/v projections are computed for the full padded sequence before block reshape;
- every encoder layer processes the full sequence;
- MLX may retain intermediate buffers in cache;
- `Memory.clearCache()` happens after the call, not inside the encoder pass;
- iOS jetsam sees total process footprint, not just active tensors.

The better conclusion is:

Block-wise attention reduces one memory term. It does not make a whole 100-second input
safe on an iPhone by itself.
### 6.5 Is There A True Streaming Granite Path Elsewhere Upstream?

I found streaming helpers in `mlx-audio-swift`, but they are for the Qwen3ASR streaming
path, not Granite Speech. They include a streaming encoder and session shape with window
buffering and state, but those types are not the Granite `generateStream(audio:)` API
used here.
Design implication:

Do not assume the upstream package has solved Granite streaming just because it has
streaming classes for another ASR model.

---
## 7. Prior-Art Synthesis
### 7.1 `PRIOR_AUDIO_PATTERNS.md`

The existing prior-art document remains the right starting point. It was scoped narrowly
to ring-buffer and chunking patterns, not to final Granite architecture decisions.

Its most relevant findings were:
- FlowScribe's 80,000-sample emit and 32,000-sample force-flush ceiling;
- Q2 Edge Chat's hardware-rate to 16 kHz conversion math;
- Python `TCCC_FEB_2026/src/audio.py` using 60-second windows with 3-second overlap.

This research extends it by answering the Granite source questions and by separating
"useful prior design idea" from "safe to lift into this app."
### 7.2 `/Users/ama/TCCC_FEB_2026`

This is the most important prior project because it is the Python prototype this Swift
app is porting.

The Python audio path uses 60-second chunks with 3-second overlap. It validates overlap
configuration, skips overlap-only final chunks, and offsets segment timestamps after
transcription. That is a useful conceptual shape: chunk metadata, overlap, and
timestamp stitching are first-class.

It is not a safe literal window size for Granite on iPhone. The Python prototype's ASR
backend and memory profile are different. The Sprint 1 Granite crash is direct evidence
that 60-second single-call audio is too large for the current iPhone path.

Sprint 2 should copy the pattern class, not the numeric constant.
### 7.3 `/Users/ama/FlowScribe`

FlowScribe uses a native Swift capture path with a 512-frame tap, resampling to 16 kHz,
and accumulation to about 80,000 samples before emission. It also has force-flush logic
around 32,000 samples and VAD-era pre-roll ideas.

The useful idea is a capture segmenter that does not send every tap buffer to ASR.

The unsafe parts are familiar: unstructured tasks, no robust back-pressure, possible
full-buffer growth, Bluetooth/network assumptions, and fallback transcript behavior that
would be unacceptable in TCCC_IOS.
### 7.4 `/Users/ama/ASR_2`

ASR_2 is very close to the FlowScribe family. It repeats the 512-frame tap, 16 kHz
resampling, about 80,000-sample batches, and VAD chunking around 512 samples.

Its most useful detail is Silero-style VAD state: fixed 512-sample chunks at 16 kHz,
small context, and state that must remain ordered. That maps to a future TCCC VAD layer.

It does not answer Granite chunking or MLX state retention.
### 7.5 `/Users/ama/fluidaudio sept`

This folder is documentation-heavy rather than source-heavy. It is still useful because
it captures prior debugging conclusions.

The durable lessons:
- VAD should see raw resampled audio, not gain-adjusted UI audio.
- About 100 ms pre-roll was useful in prior experiments.
- Ten-second buffers felt too slow for interactive use.
- Two-second or 1.5-second PTT-style chunks felt much more responsive.

The caution:

The folder does not contain enough FluidAudio Swift source to treat its streaming
internals as verified.
### 7.6 `/Users/ama/SimpleSwiftScribe`

This repo is another FlowScribe-era shape. Its current tree has limited live source, but
history shows the same pattern: native capture, resample, accumulate, then ASR.

Its main value is negative evidence. The old fixed 5-second accumulation shape is useful
as a latency comparison point, but it is not enough for a five-minute TCCC encounter
unless the pipeline has true back-pressure and chunk stitching.
### 7.7 `/Users/ama/q2-edge-chat/handy_Pi`

The Pi-class project matters because memory is much tighter than on the iPhone 17 Pro.

The useful idea is explicit model residency and small VAD frames. The path is batchy:
capture, accumulate, and transcribe after stop. It also uses queues that are not the
right final shape for iOS.

The Sprint 2 lesson is that constrained systems need bounded audio ownership, not
whole-encounter arrays.
### 7.8 `/Users/ama/q2-edge-chat/Q2 Edge Chat`

This Swift app has the most relevant modern iOS capture math outside TCCC_IOS.

It requests/handles 16 kHz mono Float32 and scales tap buffer size from hardware sample
rate to target sample rate. That is useful. The audit also found roundoff risk at
44.1 kHz because `AVAudioFrameCount` truncation can produce 4095-ish output samples
instead of exact 4096-sample chunks.

It also has a cautionary async shape: the tap launches a task, sends arrays through a
publisher, and the consumer launches more tasks. There is no explicit back-pressure.

Sprint 2 should keep the hardware-aware conversion idea but replace the plumbing with a
bounded actor-owned stream.
### 7.9 `/Users/ama/tccc-project`

This older Python/Jetson-era TCCC project contains useful chunking and VAD ideas, but
also integration drift.

The good parts:
- `AudioChunkBuffer` conceptually accumulates to target size with optional overlap.
- `ChunkSizeAdapter` can split or accumulate between different sizes.
- VAD manager tracks state/history and holdover.

The risky parts:
- the live path appears to feed very small PyAudio chunks toward STT;
- STT uses an unbounded `queue.Queue`;
- chunking helpers are not clearly wired into production;
- some verification scripts no longer match the real API.

Use it as a design sketch library, not a dependency.
### 7.10 `/Users/ama/TCCC`

This older web/TypeScript combat medic app has a WebAudio worklet that emits 4096-sample
chunks at 16 kHz, roughly 256 ms. It also has an `AudioChunk` structure with timestamp,
sequence, and duration.

The useful idea is explicit chunk metadata.

The bad lesson is silent `dropOldest` behavior and duplicated chunk risk on stop. TCCC
iOS should surface overflow and should never silently pretend the transcript is complete
if audio was dropped.
### 7.11 `/Users/ama/dictation-app`

This is browser/API-only prior art. It records a whole browser clip, converts the whole
blob to base64, and sends it to Gemini.

It is not applicable to offline Granite ingestion. The only transferable idea is UI
separation between recording state and post-processing state.
### 7.12 `/Users/ama/live-asr-transcription-demo`

This is also browser/API-only. Speech recognition comes from the browser Web Speech API.
Microphone audio is only used for waveform display.

It is useful as a reminder that live waveform/meter state can be separate from transcript
state. It does not help with MLX, Granite, or native back-pressure.
### 7.13 Cross-Project Pattern

Across the prior art, the same shape keeps appearing:
- capture buffers are small and frequent;
- ASR wants larger, semantically useful windows;
- VAD wants fixed tiny frames and ordered state;
- UI wants fast feedback;
- durable transcription wants context and overlap;
- memory-constrained systems punish whole-clip accumulation.

The Sprint 2 architecture should make those different clocks explicit instead of trying
to make one buffer size satisfy all consumers.

---
## 8. Recommendation
### 8.1 Decision

Use bounded independent Granite windows with overlap, driven by a back-pressured capture
pipeline. Treat 4 seconds as the source-backed encoder attention block duration. Treat
8-10 seconds as the likely product window if physical measurement says it is stable.
Treat 15-30 seconds as benchmark-only until proven safe.

In prompt terminology:
- Strategy A is the recommended starting architecture, corrected for the true
  context-duration math.
- Strategy B is a fallback or preview lane, not the default durable transcript lane.
- Strategy C is a ceiling-finder and possible post-processing lane, not the first
  live-capture design.
### 8.2 Why Strategy A-ish Wins For Sprint 2

It gives Sprint 2 the best balance of:
- bounded encoder input;
- fewer boundaries than 3-4 second slices;
- lower first-display latency than 20-30 second windows;
- straightforward compatibility with the current `generateStream(audio:)` API;
- no dependency on non-existent Granite encoder state retention;
- easiest path to fixing both Sprint 1 failures without a greenfield audio subsystem.

The key is to avoid overstating what the model does. This is not true streaming ASR. It
is chunked batch ASR with disciplined capture and disciplined stitching.

That is still a good Sprint 2 step.
### 8.3 Capture Architecture

The capture path should have one owner.

Recommended components:
- `AudioCaptureActor`
- `PCMResampler`
- `BoundedAudioRing`
- `ChunkSegmenter`
- `ProtectedAudioSpool`
- `GraniteChunkWorker`
- `TranscriptStitcher`
- `AudioIngestionMetrics`

The tap callback should do the minimum possible work:
- copy or borrow the PCM buffer into a preallocated pool if possible;
- enqueue into the bounded capture actor;
- update a lightweight level meter if safe;
- never spawn one detached/unstructured task per tap buffer.

The capture actor should:
- preserve ordering;
- convert to 16 kHz mono Float32;
- feed a VAD frame stream if VAD is enabled later;
- append exact sample counts into a ring;
- emit chunk descriptors when enough samples exist;
- maintain overflow counters;
- report degraded capture state to the UI.

The writer should:
- spool durable audio segments to protected storage;
- avoid holding the entire encounter as `[Float]`;
- keep enough pre-roll and overlap samples to build the next chunk;
- mark files with `NSFileProtectionComplete`.
### 8.4 Window Sizing

Initial physical sweep:
| Candidate | Purpose |
| ---: | --- |
| 4 s | true context-block baseline |
| 8 s | two-block latency/quality compromise |
| 10 s | prompt's moderate-window hypothesis |
| 15 s | lower-bound Strategy C |
| 20 s | memory ceiling probe |
| 30 s | high-risk ceiling probe |

Production default after sweep:
- Use 8 s if recall and latency are acceptable and five-minute memory is stable.
- Use 10 s if it clearly improves recall/continuity without memory creep.
- Use 4 s if 8-10 s does not remain stable.
- Do not ship 15-30 s as the live path unless five-minute memory and first-display
  latency are both acceptable.

Overlap:
- Start with 1 s overlap for 4 s windows.
- Start with 1.5-2 s overlap for 8-10 s windows.
- Keep 2-3 s overlap for 15-30 s windows if those are tested.

The overlap should be defined in samples, not floating timestamps.
### 8.5 Transcript Stitching

Stitching should happen before facts are committed into `TranscriptSegmentLedger`.

Recommended fields per chunk:
- chunk ID;
- source recording ID;
- start sample;
- end sample;
- overlap start sample;
- overlap end sample;
- Granite prompt used;
- raw transcript;
- normalized transcript;
- stitched transcript contribution;
- dropped/duplicated overlap terms;
- first-token time;
- final-token time;
- peak footprint;
- token/s.

Recommended first stitching algorithm:
1. Normalize whitespace and case for comparison only.
2. Keep original text for display.
3. Compare trailing words from previous committed text against leading words from next
   chunk.
4. Use longest common suffix/prefix match over word tokens.
5. Allow small edit distance for ASR variants.
6. Prefer retaining the later chunk when conflict occurs inside the overlap because it
   has more right-context after the boundary.
7. Mark uncertain merges for review in the research output.

This is deliberately simple. A more complex semantic stitcher can wait until the
baseline works.
### 8.6 Back-Pressure Policy

The app should not silently claim complete transcription if it drops audio.

Recommended policy:
- The ring buffer has a fixed maximum in samples or seconds.
- If the producer outruns the segmenter, drop oldest uncommitted audio only after
  emitting a metric and UI warning.
- Never drop audio that has already been assigned to a chunk descriptor.
- If overflow occurs, mark the transcript with an explicit gap event.
- Continue recording if safe, but do not hide the gap from the encounter ledger.

The UI language can be operator-simple:

`AUDIO GAP · 1.2 s not transcribed`

That is better than a clean-looking but false transcript.
### 8.7 Memory Policy

Use both process and MLX memory signals.

Process:
- `MemoryMonitor.physFootprintBytes()`
- `MemoryMonitor.availableBytes()`
- `MemoryMonitorCSVLogger`

MLX:
- `Memory.activeMemory`
- `Memory.cacheMemory`
- `Memory.peakMemory`
- `Memory.snapshot()`
- `Memory.cacheLimit`
- `Memory.clearCache()`

The benchmark should try cache limits. MLX documentation explicitly says cache limits
matter on iOS devices where jetsam applies.

Sprint 2 should not assume default MLX cache behavior is safe under sustained chunking.
### 8.8 Error Handling

Chunk failures should be local, not session-ending where possible.

Recommended behavior:
- If one Granite chunk fails, log the error with chunk metadata.
- Mark the transcript gap.
- Continue segmenting future audio if memory pressure returns to normal.
- If memory pressure is critical, stop Granite worker first, keep protected audio
  recording if safe, and tell the operator transcription is paused.
- If capture itself falls behind, surface audio gap markers.

The app must distinguish:
- capture gap;
- write failure;
- Granite inference failure;
- stitch uncertainty;
- model unavailable;
- memory pressure pause.
### 8.9 What Gets Deferred To Sprint 3

Defer:
- true encoder-state streaming unless upstream Granite exposes it;
- speculative custom encoder cache surgery;
- semantic LLM-based transcript stitcher;
- live partial ASR from Granite if chunk times are not stable;
- full VAD-driven endpointing if fixed windows solve the immediate crash;
- post-encounter high-quality re-transcription on longer windows.

Do not defer:
- bounded capture;
- physical five-minute memory profile;
- keyword recall on the TCCC fixture;
- explicit gap markers;
- source-corrected context-size notes.
### 8.10 The Pushback

The prompt says Strategy A's 10-second window "honors the encoder's designed boundary."
That is wrong for the pinned source.

Ten seconds may still win. It just does not win for that reason.

The correct reason for a 10-second default would be:
- it fits under the 6 GB cap for five minutes;
- it keeps first transcript display tolerable;
- it has better keyword recall than 4-second windows;
- it has fewer boundary failures than 3-4 second windows;
- it avoids the long-window memory risk seen in 15-30 second sweeps.

That is exactly why the physical sweep matters.

---
## 9. Risks And Unknowns
### 9.1 Physical Measurements Missing

The largest gap is obvious: this document does not contain the full physical-device
measurements requested by the prompt.

Missing:
- median/p95 mic-to-display latency;
- five-minute `phys_footprint` curves;
- per-strategy token/s;
- per-strategy keyword recall;
- transcript samples at boundaries;
- warmup amortization by chunk size;
- device-measured MLX allocation behavior around slices.

This is why the commit should remain untagged.
### 9.2 iOS Version Mismatch

The prompt mentions iOS 26.4 in one place. `SPRINT_1_ACCEPTANCE.md` records iOS 26.2.
The device must be re-identified during the final benchmark run, and the doc should be
updated with the actual OS version.
### 9.3 MLX Slice Semantics Need Device Confirmation

Source says slice is lazy and references the parent. That is enough to reject designs
that hold a long parent array and hope slicing saves memory.

It is not a substitute for measured active/cache/footprint deltas on iPhone.
### 9.4 Warm Runtime Is Not Stateful Runtime

A second call may be faster than a first call, but that does not mean the model kept
semantic audio state. Confusing these would lead to a bad Strategy C spec.
### 9.5 Boundary Recall May Surprise Us

Granite may handle short fragments better or worse than expected. TCCC vocabulary is
not generic dictation. Drug names, grid digits, call signs, and interventions are the
real target.
### 9.6 Prompt Bias Can Skew Comparisons

All strategies should use the same prompt unless the benchmark explicitly tests prompt
variants. Otherwise recall changes may reflect prompt differences rather than chunk
strategy.
### 9.7 Thermal And Sustained Performance

Five-minute runs may behave differently from isolated chunks because of thermal and
memory cache behavior. Run order should rotate or include cooldown periods.
### 9.8 Capture And Inference Can Interact

File-based replay of fixtures isolates inference. Live capture adds tap timing, writer
latency, UI updates, and audio session behavior. Sprint 2 needs both:
- file replay for repeatable inference comparison;
- live mic or simulated live feed for mailbox/back-pressure verification.
### 9.9 Prior Art Contains Abandoned Ideas

Several prior repos have useful shapes but also signs of drift, fake fallbacks,
network/cloud assumptions, or missing back-pressure. They should inform design, not
override current source evidence.
### 9.10 The App Is Safety-Critical Enough To Prefer Honest Gaps

If audio is dropped or a chunk fails, the app should expose that fact. A false sense of
complete transcription is worse than an explicit degraded state.

---
## 10. Sprint 2 Spec Preconditions
### 10.1 Take As Given

The Sprint 2 spec can take these as established unless the upstream dependency changes:
- Sprint 1 proved short Granite transcription works on the physical iPhone.
- Sprint 1 proved whole long-form transcription is unsafe.
- Sprint 1 proved current live capture has unbounded mailbox growth.
- `phys_footprint` is the jetsam-relevant process metric.
- Current `GraniteSpeechRuntime.transcribe(audioURL:)` is whole-file.
- Current `GraniteSpeechTranscriptStream` is record-then-transcribe.
- Current tap path spawns one task per copied tap buffer.
- Pinned Granite `generateStream(audio:)` does not expose encoder state continuation.
- Pinned Granite `generateStream(audio:)` creates fresh decoder KV cache per call.
- Pinned Granite `context_size=200` is about 4 seconds of raw 16 kHz audio.
- MLX slicing should not be used as a memory-saving substitute for bounded chunk
  construction.
- Apple Speech remains the default ASR; Granite is an explicit alternate.
- Model resolution must use the existing resolver/bookmark flow.
- No hidden download should occur from RECORD.
### 10.2 Decide In The Sprint 2 Spec

The Sprint 2 spec writer still needs to decide:
- exact benchmark harness surface;
- whether harness lives in app DevTools, package research target, or both;
- file replay fixture generation commands;
- live capture simulation method;
- starting `Memory.cacheLimit`;
- chunk window candidates;
- overlap duration candidates;
- keyword list source of truth;
- stitcher acceptance criteria;
- degraded-state UI copy;
- failure thresholds for stopping Strategy C;
- whether Strategy B becomes preview-only;
- whether the final production default is 4 s, 8 s, or 10 s;
- whether DD-1380 extraction consumes stitched text only or also chunk-local raw text;
- how to persist benchmark artifacts from the app container.
### 10.3 Minimum Benchmark Rows

For each run:
- device name;
- device identifier;
- iOS version;
- app commit;
- model folder source;
- model revision if known;
- strategy;
- window seconds;
- overlap seconds;
- fixture ID;
- fixture duration;
- trial number;
- chunk count;
- first display latency;
- final completion latency;
- audio-seconds per wall-second;
- p50 per-chunk latency;
- p95 per-chunk latency;
- peak `phys_footprint`;
- starting `phys_footprint`;
- ending `phys_footprint`;
- peak MLX active memory;
- peak MLX cache memory;
- peak MLX total memory;
- token/s median;
- token/s p95 or range;
- keyword recall;
- boundary failure count;
- dropped audio seconds;
- capture overflow count;
- stitch uncertainty count;
- error text if failed.
### 10.4 Minimum Acceptance Bar For The Production Path

Before the Sprint 2 production path can be considered ready:
- five-minute fixture completes without jetsam;
- five-minute live or simulated-live capture keeps bounded memory;
- peak `phys_footprint` stays below warning threshold or returns below it quickly;
- no monotonic mailbox growth;
- keyword recall on the transcribed fixture portion is at least Sprint 1's target;
- boundary samples are reviewed manually;
- dropped audio is either zero or explicitly marked;
- Apple Speech default path still works;
- Granite remains opt-in and model-folder-backed.
### 10.5 Suggested Sprint 2 Opening Move

Do not start by making the UI pretty.

Start with a small benchmark harness that can transcribe fixed file windows from a
known fixture and write rows to a durable artifact. Then add live capture segmentation.
Then pick the production window from data.

The minimal useful implementation order:
1. `AudioWindowDescriptor` and exact sample math.
2. File-based chunk replay using the existing Granite resolver.
3. Per-chunk metrics rows.
4. Stitcher prototype.
5. Strategy sweep on device.
6. Bounded capture pipeline.
7. Live capture five-minute run.
8. Production integration into `TranscriptStream`.

That order prevents the sprint from burying the core uncertainty under UI work.
### 10.6 Closing State

This document should be read as a decision aid and a correction pass, not as the final
benchmark report.

The strongest current conclusion is not "Strategy A wins forever."

The strongest current conclusion is:

Granite Speech in this repo is not stateful streaming ASR, the encoder context math is
four seconds rather than ten, the current live capture mailbox is unsafe, and Sprint 2
should implement bounded independent chunking with physical-device measurement before
choosing the final window.

That is enough to write a sharper Sprint 2 spec. It is not enough to tag the research as
complete.
