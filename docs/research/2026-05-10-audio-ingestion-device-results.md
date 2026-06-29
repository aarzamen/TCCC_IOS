# Granite Audio Ingestion Device Results

**Date:** 2026-05-10

**Device:** Aaron's iPhone, iPhone 17 Pro (`iPhone18,1`), iOS 26.2, physical device

**UDID used for launch/install:** `00008150-0018046C0188401C`

**Repo branch:** `codex/sprint-2-audio-research`

**Purpose:** convert the source-backed Sprint 2 audio ingestion research into physical
device evidence for the chunk-window decision.

---

## 1. Bottom Line

The best measured default for Sprint 2 is independent Granite Speech chunks at **8
seconds with 1 second of overlap**, fed by a bounded capture pipeline and serialized
through one Granite worker.

This was not my first clean mental model. Source inspection suggested that 4 seconds is
the closest match to the encoder's `context_size=200` block, and the original prompt
suspected 10 seconds. The device data splits the difference in a useful way:

- **4 seconds** is memory-stable and fast per chunk, but the transcript is too chopped up
  for the durable encounter record.
- **8 seconds** gives the best keyword recall in the measured sweeps, keeps p95 chunk
  latency around 1.5-1.6 seconds, and stays near 3.6 GB peak `phys_footprint`.
- **10 seconds** is viable and sometimes slightly faster overall because there are fewer
  chunks, but it costs about 380 MB more peak memory and had slightly worse recall on
  the sustained fixture.
- **15 seconds** did not jetsam in the 60-second sweep, but it was slower, heavier, and
  not better for recall. It should not be the Sprint 2 default.

The capture-side bug remains separate. These tests used file fixtures split into chunk
files; they do not make the current live `AVAudioEngine` mailbox safe. Sprint 2 still
needs bounded buffering before any chunk size matters in the hot seat.

---

## 2. Harness

I added a gated app-target benchmark path that runs only when the app is launched with
`--granite-audio-benchmark`.

Files added:

- `Packages/TCCCAudio/Sources/TCCCAudio/MLXMemoryProbe.swift`
- `TCCC_IOS/DevTools/GraniteAudioBenchmarkRunner.swift`

App entry point touched:

- `TCCC_IOS/TCCC_IOSApp.swift`

The benchmark:

- uses the existing `GraniteSpeechRuntime`;
- uses the existing `GraniteSpeechModelResolver` and bookmark store;
- does not download or restage the model;
- splits input fixtures into CAF chunks;
- transcribes chunks serially through `runtime.transcribe(audioURL:)`;
- samples `MemoryMonitor.reading().physFootprintBytes`;
- samples MLX `Memory.snapshot()` active/cache/peak counters;
- records wall time, first-token time, tokens/sec, peak memory, transcript text, and
  keyword recall;
- writes artifacts under app Documents at `GraniteAudioBenchmark/run-<timestamp>/`.

The JSON result file is newline-delimited after the final harness patch. Earlier pulled
runs still have pretty-printed JSON objects in the `.jsonl` file, but their
`SUMMARY.md` files are accurate.

---

## 3. Fixture

The long fixture was generated from `TCCC_IOS/Resources/test_5min.txt` with a slower
voice rate so it contains the actual TCCC vocabulary rather than generic speech:

```bash
say -v Alex -r 120 -o /tmp/tccc-audio-bench-fixtures/section6-slow.aiff "$(cat TCCC_IOS/Resources/test_5min.txt)"
ffmpeg -y -i /tmp/tccc-audio-bench-fixtures/section6-slow.aiff -ar 16000 -ac 1 -c:a pcm_f32le /tmp/tccc-audio-bench-fixtures/section6-slow-full.wav
ffmpeg -y -i /tmp/tccc-audio-bench-fixtures/section6-slow-full.wav -t 30 -ar 16000 -ac 1 -c:a pcm_f32le /tmp/tccc-audio-bench-fixtures/section6-30s.wav
ffmpeg -y -i /tmp/tccc-audio-bench-fixtures/section6-slow-full.wav -t 60 -ar 16000 -ac 1 -c:a pcm_f32le /tmp/tccc-audio-bench-fixtures/section6-60s.wav
```

Fixture durations:

| Fixture | Duration | Notes |
| --- | ---: | --- |
| `section6-30s.wav` | 30.00 s | early portion of the Section 6 narrative |
| `section6-60s.wav` | 60.00 s | longer stressor with more interventions |
| `section6-slow-full.wav` | 111.53 s | full slow synthesized narrative from `test_5min.txt` |

The historical bundled `test_5min.wav` is only about 14.3 seconds. It remains useful as
a short baseline, but it is not a long-form stress test.

---

## 4. Physical Runs

Build and install succeeded on the connected physical iPhone:

```bash
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'platform=iOS,id=00008150-0018046C0188401C' -configuration Debug build -skipMacroValidation
xcrun devicectl device install app --device 00008150-0018046C0188401C /Users/ama/Library/Developer/Xcode/DerivedData/TCCC_IOS-geqmlzqchxawxuhlardjkbquwppr/Build/Products/Debug-iphoneos/TCCC_IOS.app --timeout 120
```

The model resolver used the existing bookmark source in every run. Prime deltas stayed
around 2.17-2.18 GB, consistent with Sprint 1.

---

## 5. Results

### 30-Second Sweep

Run: `2026-05-10T22-11-23.854Z`

| Window | Chunks | Total wall | p50 chunk | p95 chunk | Median tokens/s | Peak footprint | Peak MLX active+cache | Recall |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 s | 10 | 8.59 s | 0.77 s | 2.07 s | 33.76 | 3484.1 MB | 3351.8 MB | 5/20, 25% |
| 8 s | 5 | 5.75 s | 1.10 s | 1.46 s | 33.96 | 3640.8 MB | 3504.7 MB | 6/20, 30% |
| 10 s | 4 | 5.17 s | 1.59 s | 1.75 s | 34.15 | 4024.2 MB | 3885.5 MB | 6/20, 30% |

The 10-second path was fastest overall on this short fixture because it made fewer
calls, but the memory jump was already visible. The 4-second path was low-memory but
had weaker continuity.

### 60-Second Sweep

Run: `2026-05-10T22-12-46.158Z`

| Window | Chunks | Total wall | p50 chunk | p95 chunk | Median tokens/s | Peak footprint | Peak MLX active+cache | Recall |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 s | 20 | 15.24 s | 0.77 s | 0.88 s | 34.51 | 3482.6 MB | 3351.9 MB | 8/20, 40% |
| 8 s | 9 | 11.57 s | 1.34 s | 1.50 s | 33.62 | 3640.4 MB | 3504.7 MB | 11/20, 55% |
| 10 s | 7 | 11.70 s | 1.82 s | 1.94 s | 28.70 | 4025.9 MB | 3885.5 MB | 9/20, 45% |
| 15 s | 5 | 12.32 s | 2.74 s | 3.17 s | 25.10 | 4517.8 MB | 4372.7 MB | 9/20, 45% |

This is the most decision-relevant sweep. Eight seconds had the best recall and roughly
tied 10 seconds on total wall time while using about 385 MB less peak footprint and
returning lower p95 chunk latency. Fifteen seconds was strictly worse for the default
live path: higher memory, higher latency, lower throughput, and no recall gain.

### 111.5-Second Sustained Runs

Runs:

- `2026-05-10T22-19-43.436Z` for 8 seconds
- `2026-05-10T22-21-33.513Z` for 10 seconds

| Window | Chunks | Total wall | p50 chunk | p95 chunk | Median tokens/s | Peak footprint | Peak MLX active+cache | Recall |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 s | 16 | 22.40 s | 1.43 s | 1.59 s | 33.39 | 3630.8 MB | 3506.2 MB | 15/20, 75% |
| 10 s | 13 | 20.67 s | 1.70 s | 1.84 s | 33.51 | 4010.4 MB | 3967.4 MB | 14/20, 70% |

Ten seconds remained viable and slightly faster overall, but the 8-second window gave
better recall, lower per-chunk tail latency, and substantially lower memory. That is the
more seamless ingestion profile for a live medic app because it lowers both the display
tail and the jetsam risk without making the transcript as fragmented as 4 seconds.

---

## 6. Transcript Continuity Notes

Four-second windows produced recognizably worse stitching. The transcript had repeated
phrase fragments, weaker grid/frequency recovery, and more clipped clinical phrases.
That supports keeping 3-4 second chunks as a possible preview lane only.

Eight-second windows preserved more of the operational structure: grid, call sign,
urgent surgical, GSW/chest, NKDA, Dawson, 6942, SpO2 changes, and the intervention
sequence. It still misheard several terms. Examples from the sustained 8-second run:

```text
break break this is medikilo 6 i have a medivac request grid co-ordinate 8734-9 404 90120 i repeat 8734 9120 call sign reaper ...
... i'm applying a vented chest seal to that exit wound now breathing is still labored ...
... giving 1g of tx gm of tx a over 10 minutes also starting 500 ml of hexton ...
```

The model often hears the right concept in a messy form. That is acceptable for Sprint 2
only if the downstream transcript cleaner or extractor is allowed to normalize known
medical/TCCC vocabulary. It is not acceptable to rely on raw ASR text alone for final DD
1380 fields.

Ten-second windows sometimes lost exact structured tokens even when the surrounding
sentence was better. In the sustained run, `9120`, `NKDA`, `Hextend`, and `RD6942` were
missed by the literal recall check, while the 8-second run recovered `9120`, `NKDA`, and
the last four `6942`.

---

## 7. MLX Slice Probe

The device-side probe allocated a 1,600,000-element `MLXArray`, evaluated it, sliced
160,000 elements, evaluated the slice, and sampled MLX `Memory.snapshot()`.

| Step | Active bytes | Cache bytes | Peak bytes |
| --- | ---: | ---: | ---: |
| start | 0 | 0 | 0 |
| after base eval | 6,406,148 | 0 | 6,406,148 |
| after slice construct | 6,406,144 | 4 | 6,406,148 |
| after slice eval | 6,406,144 | 4 | 6,406,148 |
| after clear cache | 6,406,144 | 0 | 6,406,148 |

This supports the source-backed answer that slicing does not immediately allocate a full
copy. It does not prove sliding windows are free: the slice keeps memory tied to the
underlying evaluated array, and the Granite benchmark still shows encoder activation
cost scaling with window size. Sprint 2 should chunk at the capture/file boundary rather
than keep one long parent `MLXArray` alive.

---

## 8. Decision

Sprint 2 should implement:

- a bounded 16 kHz mono capture ring;
- a writer/segmenter that emits 8-second windows with 1 second overlap;
- exactly one serialized Granite transcription worker;
- deterministic overlap stitching with a segment ledger;
- overflow/drop counters surfaced in debug logs;
- raw audio preservation separate from UI gain;
- a configurable window constant so 10 seconds can be tested again without surgery.

The default should be **8 seconds**, not 10 seconds. Ten seconds should remain a tuning
option if later field audio shows that boundary continuity matters more than the memory
and p95 latency delta. Fifteen seconds and above should be deferred to post-encounter
offline retranscription or a separate ceiling-finding path.

This test did not run a five-minute live capture. It supports the chunk-window choice,
but it does not close the capture-mailbox blocker. The next acceptance run still needs
to prove that the live tap no longer grows actor mailbox memory over several minutes.
