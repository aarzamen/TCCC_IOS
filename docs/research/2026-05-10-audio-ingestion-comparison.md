# Sprint 2 Audio Ingestion Comparison

**Date:** 2026-05-10

**Repo:** `/Users/ama/.codex/worktrees/f864/TCCC_IOS`

**Audience:** Sprint 2 planning session for the TCCC.ai iOS Granite Speech path.

**Status:** source-backed research document with a physical-device follow-up.

**Device addendum:** `docs/research/2026-05-10-audio-ingestion-device-results.md`
contains the 30 s, 60 s, and 111.5 s physical iPhone 17 Pro benchmark runs.

**Tag status:** do not tag `sprint-2-research-complete` yet. The chunk-window decision
now has physical evidence, but the five-minute live capture/back-pressure acceptance
run remains open.

**Why this document is still useful:** source inspection corrected a load-bearing
prompt assumption: Granite's `context_size=200` is about four seconds of encoder frames
in the current `mlx-audio-swift` implementation, not about ten seconds of raw audio.
The device addendum then shows that the product default should still be closer to an
8-second engineering window than to a literal 4-second encoder block.

---
## 1. Executive Summary

**Physical-device update:** after adding a gated benchmark harness and running the
connected iPhone 17 Pro, the recommended Sprint 2 default is **8-second independent
Granite chunks with 1 second overlap**. On the 60-second sweep, 8 seconds had the best
recall (11/20), near-best total wall time (11.57 s), p95 chunk wall time of 1.50 s, and
peak `phys_footprint` of 3640.4 MB. On the 111.5-second sustained fixture, 8 seconds
completed in 22.40 s with p95 chunk wall time of 1.59 s, peak `phys_footprint` of
3630.8 MB, and recall of 15/20. Ten seconds is viable but heavier; four seconds is too
fragmented for the durable transcript; fifteen seconds loses on memory, latency, and
quality. See `docs/research/2026-05-10-audio-ingestion-device-results.md` for the
measured tables.

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
2. Implement Granite transcription as independent **8-second** chunks with **1 second**
   overlap and deterministic boundary stitching.
3. Keep the window as a configurable constant so 10 seconds can be re-tested against
   real field audio, but do not hard-code 10 seconds as the model boundary.
4. Treat 3-4 second chunks as a possible low-latency preview lane, not the durable
   transcript path.
5. Treat 15 seconds and beyond as post-encounter retranscription or ceiling-finding
   territory, not the live default.

The physical addendum resolves the chunk-window blocker for file-backed Granite
transcription. It does not close the five-minute live capture/back-pressure blocker:
Sprint 2 still needs an instrumented hot-seat run proving the capture ring and writer
stay bounded while the model is consuming chunks.

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
### 2.5 Device Method And Follow-Up

The requested median/p95 latency, keyword recall, and boundary continuity required the
physical iPhone. Simulator is not acceptable because MLX on iOS simulator is not the
same runtime path and may not run the required Metal workload.

The follow-up benchmark did:
- use the existing model resolver and bookmark store;
- avoid hidden downloads;
- record `MemoryMonitor.reading().physFootprintBytes` around every chunk;
- record `STTGenerationInfo.tokensPerSecond`;
- record first-token time, final-result time, and chunk-complete time;
- write one JSONL or CSV row per chunk;
- preserve exact chunk boundary timestamps and overlap spans;
- compute keyword recall on the transcribed portion actually attempted.

The remaining completion gap is not the file-backed chunk-window choice. It is the
five-minute live capture profile with the new back-pressured capture pipeline, which
does not exist yet.
### 2.6 What I Did Not Measure Here

I did not run a five-minute live mic capture profile in this session. The physical
device follow-up used file-backed fixtures split into chunk files so it could isolate
Granite window size from the capture mailbox bug.

I attempted a local macOS SwiftPM MLX slice probe in a temporary directory to test
slice memory directly. The probe built, but execution failed because the standalone
SwiftPM executable could not load MLX's default Metal library:

`MLX error: Failed to load the default metallib. library not found`

That means the first-pass slice answer below was source-backed. The follow-up harness
then resolved it on the physical device; see the device addendum's MLX slice probe.

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
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.

Relevant Sprint 1 baseline:
- 14 s fixture completed in 5.78 s, about 2.4 audio-seconds per wall-second.
- Warm reprime measured 1.04 s.
Expected Strategy A latency:
- first transcript display latency is approximately window length plus transcribe time;
- for a 10 s window, the operator sees durable text on the order of 10-15 s after the
  first spoken words;
- for an 8 s window, first display likely lands closer to 8-12 s;
- overlap and stitching add small CPU cost but should be minor compared with Granite.
Resolved for file-backed chunks in the device addendum. True mic-input-to-display
latency remains tied to the Sprint 2 live capture pipeline.
### 3.4 Peak `phys_footprint`
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.

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
File-backed chunk peaks were measured. Five-minute steady-state live capture+transcribe
still needs device CSV after the capture pipeline is fixed.
### 3.5 Tokens/Sec Throughput
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.

The upstream `generateStream` emits `STTGenerationInfo.tokensPerSecond` after each call.
The Sprint 2 harness should persist that value per chunk.
Expected shape:
- 8-10 s chunks should amortize fixed prefill better than 3-4 s chunks;
- token/s may look deceptively healthy even if first-token latency is poor;
- report both token/s and wall-clock chunk completion.
Resolved for file-backed chunks in the device addendum.
### 3.6 Keyword Recall
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.

Strategy A should be evaluated against the v1 Section 6 token list already visible in
`GraniteBakeoffView`. The recall denominator must be restricted to the fixture portion
actually transcribed.
Expected behavior:
- ten-ish second windows may preserve enough local context for TCCC phrases;
- one to two seconds of overlap should recover most word cuts;
- deterministic dedupe is needed so overlapped drugs and vitals are not double-applied
  into the encounter ledger.
Resolved for the 30 s, 60 s, and 111.5 s file-backed fixtures in the device addendum.
### 3.7 Boundary Continuity
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected continuity risk:
- a phrase such as "needle decompression" can split across windows;
- medication plus dose can split across windows;
- call sign or grid digits can be duplicated or dropped at overlap boundaries.

Recommended annotation in the benchmark output:
- print the last 15 words of chunk N;
- print the first 15 words of chunk N+1;
- print the stitched span;
- mark whether the overlap deduper kept, dropped, or merged each repeated phrase.
Resolved for file-backed chunking in the device addendum.
### 3.8 Encoder Warmup Amortization
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.

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
First source pass: source-inspected only. Physical follow-up sampled MLX active/cache
memory per chunk and is summarized in the device addendum.

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
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected behavior:
- first durable text can appear after about 3-4 seconds plus inference time;
- if inference is faster than real time, perceived latency may be tolerable;
- if fixed overhead dominates, the worker can fall behind sustained speech.

The key metric is not one isolated 4 s chunk. The metric is whether a five-minute stream
keeps queue depth bounded while the operator keeps talking.
File-backed 4-second chunks had the lowest per-chunk wall time, but the transcript was
too fragmented. Queue depth still needs the live capture implementation.
### 4.4 Peak `phys_footprint`
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected memory profile:
- best per-call activation bound among A/B/C;
- more total calls, more opportunities for cache fragmentation;
- possible stable sawtooth if cache limit is configured;
- possible monotonic growth if same-size repeated calls still accumulate retained
  buffers or if capture queues are not bounded.

Strategy B will not rescue a bad capture pipeline. If tap callbacks keep spawning tasks,
3-second chunking only moves the bottleneck.
Five-minute live capture profile still needed.
### 4.5 Tokens/Sec Throughput
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected behavior:
- token/s may be lower than Strategy A because prefill/setup happens more often;
- warm-start effects may hide the cost in short tests;
- a sustained five-minute run is required.

The Sprint 1 warm reprime of 1.04 s is the warning sign. If a 3 s slice spends around
one second on fixed overhead, roughly a quarter to a third of the budget is overhead
before useful decode is considered.
### 4.6 Keyword Recall
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected risk:
- 3-4 s windows may split many TCCC facts;
- overlap can help, but overlap consumes a larger fraction of each slice;
- too much overlap can duplicate facts and inflate downstream extraction events.

Strategy B needs a stronger boundary ledger than A because boundaries occur more often.
### 4.7 Boundary Continuity
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected continuity:
- higher risk of clipped clauses;
- higher risk of repeated partial words;
- better recovery if each chunk is short enough that the model does not drift.

The benchmark should compare 3 s, 4 s, and 4 s with 1 s overlap. It should not report
"Strategy B" as one number.
### 4.8 Encoder Warmup Amortization
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.

This is the central downside.

The correct calculation is:

`overheadPercent = fixedPerChunkTime / totalChunkWallTime`

If the chunk is 4 s of speech and the model takes 1.6 s wall time, then fixed overhead
is tolerable only if most of that 1.6 s is useful compute. If the chunk takes 3-5 s wall
time, the worker falls behind.
### 4.9 MLX Allocation Pattern
First source pass: source-inspected only. Physical follow-up sampled MLX active/cache
memory per chunk and is summarized in the device addendum.

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
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected behavior:
- 15 s window: first durable text likely too slow for live extraction but maybe
  acceptable for record-and-review.
- 20 s window: likely starts to feel batchy.
- 30 s window: likely unacceptable as the only live display path, even if memory fits.

Strategy C may still be valuable for post-encounter re-transcription or high-quality
repair after a lower-latency preview lane.
The measured 15-second file-backed run had p95 chunk wall time of 3.17 seconds on the
60-second fixture, worse than the 8-second and 10-second alternatives.
### 5.4 Peak `phys_footprint`
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
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
The measured 15-second file-backed run peaked at 4517.8 MB `phys_footprint`, about
877 MB above 8-second chunks on the same fixture, with no recall gain.
### 5.5 Tokens/Sec Throughput
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected behavior:
- if memory fits, longer windows should amortize fixed setup better;
- token/s alone may look better while operator latency gets worse;
- the benchmark should report both generation token/s and audio-seconds/wall-second.
### 5.6 Keyword Recall
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected behavior:
- best chance of preserving long clauses and phrase context;
- lower boundary count;
- possible degradation if long audio causes memory pressure or incomplete output.

If Strategy C can complete the full five-minute fixture through 30-second windows, it
may produce the best durable transcript. That is plausible enough to test, but not
plausible enough to assume.
### 5.7 Boundary Continuity
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected behavior:
- fewer boundaries than A/B;
- fewer stitch points;
- larger loss if a chunk fails.

Boundary stitching remains necessary because every call is independent.
### 5.8 Encoder Warmup Amortization
First source pass: not measured. Physical follow-up results are summarized in the
device addendum.
Expected behavior:
- best amortization among the independent-window strategies;
- worst first-display latency;
- risk that memory headroom disappears before amortization matters.
### 5.9 MLX Allocation Pattern
First source pass: source-inspected only. Physical follow-up sampled MLX active/cache
memory per chunk and is summarized in the device addendum.

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
Resolved on the physical iPhone in the device addendum. The slice probe did not show a
new full-size allocation at slice construction or `eval(slice)`, but active memory
remained tied to the evaluated base/slice. That supports chunking before MLX arrays are
created, not slicing one long parent array.
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
still be tested, but the physical sweep favored 8-second windows for the live default.
That is a product latency/quality/memory decision, not the native context size.
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
**8 seconds with 1 second overlap** as the measured Sprint 2 live default. Treat 10
seconds as a tuning option, and treat 15-30 seconds as benchmark/post-encounter
territory until proven safe for live capture.

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

Physical sweep:
| Candidate | Purpose |
| ---: | --- |
| 4 s | true context-block baseline; stable but too fragmented |
| 8 s | measured live default candidate; best quality/memory/latency tradeoff |
| 10 s | viable tuning option; faster overall in sustained run but heavier |
| 15 s | lower-bound Strategy C; worse memory/latency without recall gain |
| 20 s | unneeded for Sprint 2 default after 15 s result |
| 30 s | high-risk ceiling probe/post-encounter only |

Production default after sweep:
- Use 8 s as the default for the first live implementation.
- Keep 10 s as a runtime/config constant for field retesting.
- Use 4 s only as a fallback or preview lane if live capture memory forces it.
- Do not ship 15-30 s as the live path unless five-minute memory and first-display
  latency are both acceptable.

Overlap:
- Start with 1 s overlap for 4 s windows.
- Start with 1 s overlap for 8 s windows because that is what was measured.
- Test 1.5-2 s overlap later only if boundary errors remain material.
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

This is why the commit should remain untagged as full research completion, even though
the file-backed chunk-window decision now has physical evidence.
### 9.2 iOS Version Mismatch

The prompt mentions iOS 26.4 in one place. The physical benchmark device reported iOS
26.2 through `devicectl`. Future runs should keep recording the actual OS version
instead of trusting prompt memory.
### 9.3 MLX Slice Semantics Are Narrowly Measured

The physical slice probe supports the source answer that simple slicing is not an eager
full copy. That is enough to reject designs that hold a long parent array and hope
slicing saves memory. It is not a full proof for every MLX slicing path or downstream
operation.
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
- whether the benchmark harness remains app DevTools-only or gets promoted into a
  package research target as well;
- file replay fixture generation commands;
- live capture simulation method;
- starting `Memory.cacheLimit`;
- whether to expose the 8-second default as a debug-tunable setting;
- whether to test 1.5-2 s overlap after the 1 s overlap baseline;
- keyword list source of truth;
- stitcher acceptance criteria;
- degraded-state UI copy;
- failure thresholds for any future Strategy C ceiling probe;
- whether Strategy B becomes preview-only or is dropped entirely;
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

Start from the benchmark harness that now transcribes fixed file windows from a known
fixture and writes rows to a durable artifact. Then add live capture segmentation and
prove the capture side stays bounded.

The minimal useful implementation order:
1. `AudioWindowDescriptor` and exact sample math.
2. Bounded capture pipeline.
3. Live segmenter emitting 8 s / 1 s overlap descriptors.
4. Stitcher prototype using the file-backed benchmark text.
5. Per-chunk metrics rows in the live path.
6. Live capture five-minute run.
7. Production integration into `TranscriptStream`.
8. Optional 10 s retest after the live path is stable.

That order prevents the sprint from burying the core uncertainty under UI work.
### 10.6 Closing State

This document should be read as a decision aid and correction pass, with the physical
device addendum as the current benchmark report.

The strongest current conclusion is not "Strategy A wins forever."

The strongest current conclusion is:

Granite Speech in this repo is not stateful streaming ASR, the encoder context math is
four seconds rather than ten, the current live capture mailbox is unsafe, and the best
measured Sprint 2 default is bounded independent 8-second chunking with 1 second
overlap.

That is enough to write a sharper Sprint 2 spec. It is still not enough to tag the
research as complete until the live capture/back-pressure run is measured.
