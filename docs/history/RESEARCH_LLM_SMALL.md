# Qwen 3 1.7B vs Liquid LFM2-1.2B for TCCC.ai on iPhone 17 Pro

**Date:** 2026-05-05
**Target device:** iPhone 17 Pro, A19 Pro, 12 GB unified RAM, iOS 26.2
**Goal:** Pick a small open-weight LLM whose license tolerates medical + military use, fits comfortably under iOS jetsam, and matches Apple Foundation Models on the four TCCC.ai use cases (MEDEVAC radio script, encounter narrative, ZMIST handoff, TranscriptCleaner).
**Predecessor:** `RESEARCH_LLAMA32B.md` flagged that Llama 3.2 3B will not load on iPhone 17 Pro under MLX (jetsam ceiling ~6 GB), and that Llama 3.2's AUP forbids both military and unauthorized medical use. We need a non-Llama replacement.

---

## TL;DR

**Pick LFM2.5-1.2B-Instruct first; keep Qwen 3 1.7B as a fall-back.** Both fit, both have permissive licenses for our use cases, and both are credibly faster and more accurate at this size class than Llama 3.2 1B. The deciding factors:

1. **License cleanliness.** Qwen 3 ships under standard **Apache 2.0** with no AUP. LFM2 ships under **LFM Open License v1.0**, which is "Apache 2.0 with one extra clause" — a $10 M annual-revenue cap on commercial use, but **no field-of-use restrictions** (no military/medical/weapons clauses). Both are usable for TCCC.ai. Apache 2.0 is the simpler answer for a sideloaded prototype that may someday be open-sourced.
2. **Benchmarks at this size.** LFM2-1.2B beats Qwen 3 1.7B on **IFEval (74.89 vs 73.98), GSM8K (58.3 vs 51.4), GPQA (31.47 vs 27.72)** despite being smaller. Qwen 3 1.7B wins on raw knowledge — **MMLU 59.11 vs 55.23**, MGSM 66.56 vs 55.04 — and has a thinking-mode toggle. For TCCC.ai's prompt-discipline-heavy use cases, IFEval is the most important metric, and LFM2 wins it.
3. **iPhone 17 Pro performance (Takkar, 8 Feb 2026).** All four candidates loaded cleanly:
   - Qwen 3 0.6B 4-bit: **62.2 tok/s, 163 ms TTFT, 351 MB on disk**
   - **LFM2.5-1.2B 4-bit: 59.7 tok/s, 244 ms TTFT, 663 MB**
   - Llama 3.2 1B 4-bit: 58.1 tok/s, 253 ms TTFT, 713 MB
   - Qwen 3 1.7B 4-bit: 39.5 tok/s, 360 ms TTFT, 984 MB
   - Llama 3.2 3B: **could not load** (jetsam, per the same benchmark)
4. **Architecture novelty.** LFM2 is a hybrid: 10 short-convolution blocks + 6 GQA-attention blocks. The conv blocks have O(n) complexity vs O(n²) for attention, which is why LFM2 hits iPad TPS levels (124 TPS) that Qwen 3 1.7B (61.5) can't touch — the smaller KV-cache and short-conv compute load is exactly the shape Apple Silicon's CPU+GPU hybrid likes. For our typical ~500-token prompts the gain is real but modest; it would be larger at long context.

**Recommendation in one line:** scaffold a `TCCCLLMBackend` protocol now (stubbed), bundle nothing, plan for a first-launch download of `LFM2.5-1.2B-Instruct-4bit-MLX` (~660 MB) gated behind a single user-confirmed network call, and keep Apple Foundation Models as the default backend until the LFM2 path proves itself on the four real prompts.

---

## 1. Qwen 3 1.7B

### License — Apache-2.0, no AUP

The Qwen 3 dense models including 1.7B ship under **Apache-2.0**. No acceptable-use policy, no field-of-use restrictions. The HF model card confirms `license: apache-2.0`. Past Qwen releases (Qwen 1, Qwen 2) had a custom Tongyi Qianwen license with some "do not use against China's national interests" language, but **Qwen 3 dropped that** — the entire dense Qwen 3 family (0.6B / 1.7B / 4B / 8B / 14B / 32B) is straight Apache 2.0. The MoE variants (Qwen3-235B-A22B, etc.) also Apache 2.0.

This is the cleanest license you can get short of public-domain. Patent grant included, distribution allowed, modification allowed, military and medical use are simply not addressed (and therefore not prohibited).

### Sources

- Model card: https://huggingface.co/Qwen/Qwen3-1.7B
- GGUF: https://huggingface.co/Qwen/Qwen3-1.7B-GGUF (Qwen team's own GGUF)
- MLX 4-bit: https://huggingface.co/mlx-community/Qwen3-1.7B-4bit (official mlx-community port, 968 MB)
- Technical report: https://arxiv.org/abs/2505.09388 (May 2025)
- Release date: **2025-04-29**

### Spec

- **Parameters:** 1.7 B total, 1.4 B non-embedding
- **Architecture:** decoder-only transformer, 28 layers, GQA with 16 query / 8 KV heads
- **Tokenizer:** Qwen 3 BPE, ~151 k vocab (large, but shared with the entire Qwen 3 family — useful if you ever swap to a 4B / 8B sibling)
- **Context window:** 32 768 tokens
- **Languages:** 100+ (including English; multilingual is a side-effect rather than a primary use case)
- **Modes:** unique to Qwen 3 — `enable_thinking=True` puts the model in a long-reasoning mode (longer outputs, slower, better on math/coding), while `enable_thinking=False` is the standard fast mode. For TCCC.ai, **always keep thinking off** — we want fast, deterministic, schema-following output, not chain-of-thought.

### Quantizations

The Qwen team only publishes Q8_0 GGUF themselves (1.83 GB), but `bartowski/Qwen3-1.7B-GGUF` and `unsloth/Qwen3-1.7B-GGUF` are widely-used third-party GGUFs covering the full Q4 / Q5 / Q6 range. Approximate sizes for 1.7B:

| Quant       | Size on disk | Notes                                         |
|-------------|--------------|-----------------------------------------------|
| MLX 4-bit   | **968 MB**   | mlx-community official; what Takkar tested    |
| GGUF Q4_K_M | ~1.1 GB      | llama.cpp sweet spot                          |
| GGUF Q5_K_M | ~1.25 GB     | small quality bump                            |
| GGUF Q6_K   | ~1.45 GB     | near-lossless                                 |
| GGUF Q8_0   | 1.83 GB      | Qwen team's own publish                       |
| BF16        | ~3.4 GB      | full precision; too big                       |

### Benchmarks

The Qwen 3 technical report's Table 8 reports **base-model** numbers for 1.7B (compared against Qwen 2.5-1.5B and Gemma-3-1B; Llama 3.2 isn't in the table):

| Bench    | Qwen3-1.7B-Base |
|----------|-----------------|
| MMLU     | 62.63           |
| GSM8K    | 75.44           |
| MATH     | 43.50           |
| HumanEval (EvalPlus) | 52.70 |
| GPQA     | 28.28           |

**Instruct numbers** (post-training tuning, what we'd actually use) reported by EvalScope and the LFM2 model card:

| Bench    | Qwen3-1.7B-Instruct |
|----------|---------------------|
| MMLU     | 59.11               |
| MMLU-Pro | 68.67               |
| MMLU-Redux | 92.77             |
| IFEval (prompt-strict) | 81.93 |
| IFEval (inst-strict) | 87.75 |
| IFEval (overall, LFM2 card) | 73.98 |
| GSM8K    | 51.4                |
| MGSM (multilingual math) | 66.56 |
| GPQA     | 27.72               |

Versus Llama 3.2 1B Instruct (from `RESEARCH_LLAMA32B.md` and the LFM2 card):

| Bench       | Llama 3.2 1B | Qwen3-1.7B | Δ              |
|-------------|--------------|------------|----------------|
| MMLU        | 46.6         | 59.11      | +12.5          |
| IFEval      | 52.39        | 73.98      | **+21.6**      |
| GSM8K       | 35.71        | 51.4       | +15.7          |
| GPQA        | 28.84        | 27.72      | -1.1           |

Versus Llama 3.2 3B Instruct (the model that wouldn't fit):

| Bench       | Llama 3.2 3B | Qwen3-1.7B | Δ          |
|-------------|--------------|------------|------------|
| MMLU        | 63.4         | 59.11      | -4.3       |
| IFEval      | 77.4         | 73.98      | -3.4       |

So **Qwen 3 1.7B is roughly 90 % of Llama 3.2 3B on the metrics that matter, at 56 % of the disk size, with no license problem**. That's a strong place to be.

### iOS integration

- **MLX-Swift:** `mlx-community/Qwen3-1.7B-4bit` is in the same format as every other model in the `mlx-community` namespace. `MLXLanguageModel` (via `AnyLanguageModel`) loads it with one line.
- **llama.cpp:** Qwen 3 architecture support landed in llama.cpp in May 2025 (around the time of release). Works in `tattn/LocalLLMClient`'s GGUF backend without any patches.
- **Known iOS apps that bundle Qwen 3:** several MLX-based iOS demo projects in `mlx-swift-examples` swap to Qwen 3 in their model picker. No medical/clinical iOS app I could find ships Qwen 3 1.7B publicly, so we'd be pioneering the use case.

---

## 2. Liquid AI LFM2 family

### Family layout (as of May 2026)

Liquid AI has shipped LFM2 in waves. As of this writing the relevant text-generation checkpoints are:

| Model                         | Params  | Notes |
|-------------------------------|---------|-------|
| LFM2-350M                     | 0.35 B  | Tiny edge; too small for our use |
| LFM2-700M                     | 0.7 B   |       |
| **LFM2-1.2B**                 | 1.17 B  | First-gen 1.2B (July 2025) |
| **LFM2.5-1.2B-Instruct**      | 1.17 B  | Refresh; the version Takkar benchmarked. Pick this one. |
| LFM2-2.6B                     | 2.6 B   | Probably loadable on iPhone 17 Pro at Q4 but not yet benchmarked |
| LFM2-8B-A1B                   | 8 B MoE / 1 B active | Uses the new `lfm2moe` arch — llama.cpp support landed Oct 2025 |
| LFM2-VL-450M / 1.6B           | vision  | Out of scope |
| LFM2-Audio-1.5B               | audio   | Out of scope |

**The target is LFM2.5-1.2B-Instruct.** It's the latest text-only refresh, instruction-tuned, has a clean MLX 4-bit port, and is what the iPhone 17 Pro benchmarks reference.

- Model card: https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct
- GGUF: https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF
- MLX 4-bit: https://huggingface.co/mlx-community/LFM2-1.2B-4bit (659 MB, mlx-lm 0.26.0)

### License — LFM Open License v1.0

This is the part that surprised me most. The LFM Open License is **Apache 2.0 with exactly one substantive change**: a $10 million annual-revenue threshold for commercial use. Above the threshold you have to negotiate a paid commercial license; below it (and for non-commercial / research / personal use), it behaves exactly like Apache 2.0.

What it does NOT contain (confirmed by reading the full license at https://www.liquid.ai/lfm-license and the LICENSE file shipped with each HF repo):

- **No** acceptable-use policy
- **No** military prohibition
- **No** medical / health-care prohibition
- **No** weapons prohibition
- **No** "harmful applications" clause
- **No** dual-use restrictions
- **No** field-of-use limitations of any kind beyond the revenue cap

This is genuinely better than Llama 3.2's license for TCCC.ai, and roughly as permissive as Apache 2.0 for any organization under $10 M revenue. For a single-medic personal sideload it is **strictly** better than Llama (no prohibition lurking) and **equivalent in practice** to Qwen 3's Apache-2.0.

**Caveat:** there's an HF community thread on `LFM2-2.6B-Exp-GGUF` (https://huggingface.co/LiquidAI/LFM2-2.6B-Exp-GGUF/discussions/3) titled "LFM Open License v1.0 isn't free license" complaining about the revenue cap. That's correct in the OSI-purist sense (it isn't a *free / libre* license like Apache 2.0), but it's still a permissive license for all practical purposes for our use case. Don't conflate "not OSI-approved" with "doesn't permit our use."

### Architecture — why this matters for memory

LFM2 is a **hybrid Liquid model**: 16 blocks total = 10 double-gated short-range LIV convolution blocks + 6 grouped-query-attention blocks. This is novel and the implications are non-obvious:

- **Short convolutions are O(n)**, attention is O(n²) on sequence length. At our typical context sizes (~500–4 000 tokens) the conv-block speedup over a pure-attention 1.2 B model is real but modest — maybe 1.5–2× decode speedup on CPU. At long context (32k) it's much larger.
- **KV cache only allocates on the 6 attention layers**, not 16. The conv layers' state is a fixed-size convolution buffer per layer, not context-length-scaled. So **at 4k context with 6 attention layers × 8 KV heads × 128 dim × 2 (K+V) × FP16 ≈ ~50 MB of attention KV cache**, vs ~300 MB for a comparably-parameterized full-attention model. That's a meaningful headroom win on iPhone where every 50 MB matters.
- The architecture was explicitly designed for "embedded SoC CPU" workloads. Apple Silicon's Performance + Efficiency core mix benefits the same way ARM SoCs do. The Mac Mini M4 hits 1 427 tok/s prefill, 122 tok/s decode on LFM2-1.2B-Q4_0, which is 2× what Qwen3-1.7B does on the same hardware.

**Catch:** the hybrid architecture means LFM2 is **less battle-tested in third-party tooling**. llama.cpp added LFM2 support in **PR #14620** (text models) — fully merged and stable since mid-2025. MLX-LM added LFM2 in **release 0.21** and the conversions in `mlx-community` are clean. LFM2-MoE (a different architecture, `lfm2moe`) only landed in llama.cpp in October 2025. We'd be on a stable code path for LFM2.5-1.2B specifically.

### Spec

- **Parameters:** 1.17 B (1 170 340 608)
- **Layers:** 16 hybrid (10 short-conv + 6 GQA-attention)
- **Vocabulary:** 65 536 (notably smaller than Qwen 3's 151 k — saves tokenizer table memory and embedding-matrix memory)
- **Context window:** 32 768 tokens
- **Languages:** 8 (English, Arabic, Chinese, French, German, Japanese, Korean, Spanish). For TCCC.ai (English-first) this is fine.
- **Training budget:** 10 trillion tokens (very high for a 1.2 B model)
- **Recommended sampling:** `temperature=0.3, min_p=0.15, repetition_penalty=1.05`
- **Chat template:** ChatML-style, `<|im_start|>{role}\n...<|im_end|>`

### Quantizations

Confirmed sizes from `LiquidAI/LFM2-1.2B-GGUF`:

| Quant       | Size on disk |
|-------------|--------------|
| MLX 4-bit   | **659 MB**   |
| GGUF Q4_0   | 696 MB       |
| GGUF Q4_K_M | **796 MB**   |
| GGUF Q5_K_M | 843 MB       |
| GGUF Q6_K   | 963 MB       |
| GGUF Q8_0   | 1.25 GB      |
| F16         | 2.34 GB      |

LFM2-1.2B-MLX-4bit at 659 MB is the smallest credible-quality model we'd consider, and it leaves ample resident-memory headroom alongside Speech and the SwiftUI front end.

### Benchmarks

From the `LiquidAI/LFM2-1.2B` model card (their published numbers; treat as somewhat self-promotional but generally consistent with third-party leaderboards):

| Bench   | LFM2-1.2B   | Qwen3-1.7B | Llama 3.2-1B |
|---------|-------------|------------|--------------|
| MMLU    | 55.23       | **59.11**  | 46.6         |
| GPQA    | **31.47**   | 27.72      | 28.84        |
| IFEval  | **74.89**   | 73.98      | 52.39        |
| GSM8K   | **58.3**    | 51.4       | 35.71        |
| MGSM    | 55.04       | **66.56**  | 29.12        |
| MMMLU   | **46.73**   | 46.51      | 38.15        |

**Read.** LFM2 wins or ties on 4 of 6, including the two we care about most: **IFEval** (instruction following, the make-or-break metric for our prompt-disciplined use cases) and **GSM8K** (multi-step reasoning, relevant to ZMIST formatting). Qwen 3 wins on raw knowledge (MMLU) and multilingual math (MGSM). For TCCC.ai's English-only, prompt-rigid pipeline, **LFM2 is the better fit per benchmark**.

Liquid claims 2× faster decode and prefill on CPU vs Qwen 3 — confirmed by the iPhone 17 Pro numbers below where LFM2.5-1.2B beats Qwen 3 1.7B by ~50 % at decode despite being only 30 % smaller in parameter count.

### iOS integration

- **MLX-Swift:** clean port at `mlx-community/LFM2-1.2B-4bit`. Loadable via `AnyLanguageModel`'s MLX backend.
- **llama.cpp:** PR #14620 merged ~mid-2025; LFM2-1.2B-Instruct-GGUF runs in any recent llama.cpp build. Verified by Liquid's own docs at https://docs.liquid.ai/deployment/on-device/llama-cpp.
- **`LocalLLMClient`:** loads LFM2 GGUF transparently as long as the underlying llama.cpp version is recent.
- **Known iOS deployments:** LFM2 is the model Liquid actively markets for on-device. The Liquid Playground app on iOS uses it. No public clinical iOS apps yet.

---

## 3. iPhone 17 Pro deployment feasibility

The single most useful primary source here is **Ricky Takkar, "How Fast Are On-Device LLMs on iPhone 17 Pro and iPad Pro?" (8 Feb 2026)**, which benchmarks every candidate we care about under a controlled methodology (greedy decode, EOS ignored, fixed output length, three prompt-size buckets short / medium / long).

### Headline tok/s and TTFT (medium prompt, p50)

| Model               | Disk  | iPhone 17 Pro | iPad M5 | iPhone TTFT |
|---------------------|-------|---------------|---------|-------------|
| Qwen 3 0.6B 4-bit   | 351 MB | 62.2 tok/s   | 86.1    | 163 ms      |
| LFM2.5-1.2B 4-bit   | 663 MB | **59.7**     | **124.1** | 244 ms    |
| Llama 3.2 1B 4-bit  | 713 MB | 58.1         | 117.9   | 253 ms      |
| LFM2.5-1.2B 6-bit   | 951 MB | 45.4         | 88.4    | 280 ms      |
| Qwen 3 1.7B 4-bit   | 984 MB | 39.5         | 61.5    | 360 ms      |
| Llama 3.2 3B 4-bit  | -      | **could not load — exceeded jetsam ceiling** |

**Reading.** All four sub-1 GB candidates load comfortably on iPhone 17 Pro and run at "feels native" speeds (>30 tok/s is the threshold below which generation stops feeling instant). **Qwen 3 1.7B at 4-bit is the largest model that loads cleanly**, at 39.5 tok/s — usable but the slowest of the bunch. **LFM2.5-1.2B 4-bit hits 59.7 tok/s**, only 4 % behind the 0.6B Qwen at less than half the param-count gap.

### Memory headroom

iPhone 17 Pro: 12 GB RAM total, jetsam foreground ceiling ~6 GB unentitled, ~9 GB with `com.apple.developer.kernel.increased-memory-limit` (free Apple ID supports it via SideStore 2.2+). The TCCC.ai app's resident footprint at full operation is estimated at 600–900 MB (SwiftUI views, `SpeechRecognizer` actor with audio ring buffer, `Canvas` ECG, photo-library bridge during export).

For the candidates:

| Model              | Weights | KV @ 4k (FP16) | Compute scratch | Total resident |
|--------------------|---------|----------------|-----------------|----------------|
| LFM2.5-1.2B 4-bit  | 660 MB  | ~50 MB (only 6 attn layers) | ~150 MB | **~860 MB**  |
| Qwen 3 1.7B 4-bit  | 970 MB  | ~150 MB (28 attn layers)    | ~250 MB | **~1.37 GB** |
| Llama 3.2 1B 4-bit | 710 MB  | ~140 MB                      | ~200 MB | **~1.05 GB** |

Adding the 700–900 MB app baseline:

- LFM2.5: **~1.7 GB total resident** — comfortable on a 6 GB unentitled iPhone, fine even with Foundation Models also loaded (~2 GB) for an A/B-comparison build.
- Qwen 3 1.7B: **~2.2 GB total resident** — also comfortable; would not co-resident with FoundationModels under the unentitled ceiling, would under the 9 GB entitled ceiling.

**Conclusion:** both fit. LFM2.5-1.2B leaves more headroom because its hybrid architecture has a smaller KV cache than a pure-attention 1.2 B equivalent.

### TCCC.ai workload latency estimates

Using ~500 prompt tokens / 100–500 output tokens, with LFM2.5-1.2B 4-bit at 59.7 tok/s decode and ~244 ms TTFT:

- **Radio script** (~150 prompt → 120 output): ~244 ms TTFT + 2.0 s decode = **~2.3 s**
- **Encounter narrative** (~300 prompt → 70 output): ~2 s TTFT-equivalent + 1.2 s = **~2 s**
- **ZMIST** (~400 prompt → 150 output): ~3 s
- **TranscriptCleaner** (~500 prompt → 500 output): ~8 s — the slow one. Same length-in length-out task for Qwen 3 1.7B at 39.5 tok/s would be ~13 s. For Apple Foundation Models on the ANE it's <2 s.

So **LFM2.5 is roughly 4× slower than Apple Foundation Models on the longest task, but still tolerable for a one-shot post-event handoff**. The cleaner is also the task where the swap is most worth it (Apple's safety filters refuse some clinical phrasings).

---

## 4. Integration path

### Wrappers

| Library                   | Status (May 2026) | Verdict |
|---------------------------|-------------------|---------|
| `mattt/AnyLanguageModel`  | v0.8.0, March 2026, **23 releases**, actively maintained | Best fit. API mirrors Apple's `LanguageModelSession` so the swap from current `TCCCLanguageModel` is one line. Backends: Apple FoundationModels, MLX, llama.cpp, CoreML, Ollama, plus cloud (which we never use). Swift 6.1+, iOS 17+. **Pick this.** |
| `tattn/LocalLLMClient`    | v0.5.0, April 2026, 15 releases | Solid alternative. Backends: llama.cpp, MLX, FoundationModels. Lower-level `LLMSession` API rather than a 1:1 Apple mirror. Self-describes as "experimental, API may change." |
| `mlx-swift-examples` direct | Stable upstream | Most code, no third-party wrapper risk. Use if AnyLanguageModel and LocalLLMClient both prove flaky. |
| `llama.cpp.swift` (`ggml-org/llama.cpp` Swift Package) | Stable, official | Pure llama.cpp path. More verbose API. Best if we want maximum control over the GGUF runtime. |

**Pick:** `AnyLanguageModel` as the abstraction, MLX as the primary backend (faster on Apple Silicon than GGUF for the same quant), llama.cpp as a fallback if MLX porting gets stuck on a future model.

### Caveats

- **AnyLanguageModel known issue:** "A bug in Xcode 26 may cause build errors when targeting macOS 15 / iOS 18 or earlier with conformance errors. Workaround: build with Xcode 16." We're on Xcode 26.2 / iOS 26.2 deployment target, so this doesn't bite us.
- **MLX KV-cache greediness** (`ml-explore/mlx-examples #1025`): MLX allocates KV cache up to maximum context up-front. This was a real problem for Llama 3.2 3B on iPhone (the bulk of why it can't load). At 1.2 B parameters with only 6 attention layers in LFM2's case, the KV cache is small enough that the issue doesn't bite. For Qwen 3 1.7B with 28 attention layers it's marginal — set `kv_cache_max_tokens=4096` explicitly to keep allocation bounded.

---

## 5. Stub-then-real implementation sketch

The current `TCCCLanguageModel` is a single actor wrapping Apple's `LanguageModelSession`. To support multiple backends, refactor to a protocol with a default Apple implementation and stub implementations for each open-weight backend.

### File layout

```
TCCC_IOS/Intelligence/
├── TCCCLLMBackend.swift               (NEW — protocol)
├── TCCCLanguageModel.swift            (existing — refactored to conform)
├── AppleFoundationModelBackend.swift  (NEW — wraps existing FoundationModels code)
├── MLXBackend.swift                   (NEW — stub then real, MLX-Swift via AnyLanguageModel)
├── LlamaCppBackend.swift              (NEW — stub then real, GGUF via AnyLanguageModel)
├── ModelDownloader.swift              (NEW — first-launch HTTPS GET, SHA-256 verify)
├── EncounterNarrativeGenerator.swift  (existing — unchanged)
├── RadioScriptGenerator.swift         (existing — unchanged)
├── ZMISTNarrativeGenerator.swift      (existing — unchanged)
└── TranscriptCleaner.swift            (existing — unchanged)
```

### Protocol shape

```swift
protocol TCCCLLMBackend: Actor {
    enum BackendError: Error {
        case unavailable(reason: String)
        case modelNotDownloaded
        case generationFailed(String)
    }

    /// Backend identifier for Settings UI ("Apple Foundation", "Qwen 3 1.7B (MLX)", "LFM2.5 1.2B (MLX)")
    nonisolated var displayName: String { get }

    /// Is the backend ready right now? (Apple model installed, weights downloaded, etc.)
    func isReady() async -> Bool

    /// One-shot generation. The generator classes (RadioScriptGenerator, etc.)
    /// call this and don't care which backend is behind it.
    func generate(instructions: String, prompt: String) async throws -> String

    /// Clear any in-memory chat state. Called between unrelated tasks.
    func reset() async
}
```

### Stub backend (compiles, runtime errors)

```swift
actor MLXBackend: TCCCLLMBackend {
    nonisolated let displayName = "LFM2.5-1.2B (MLX)"
    private let modelId: String  // "mlx-community/LFM2-1.2B-4bit"

    init(modelId: String) { self.modelId = modelId }

    func isReady() async -> Bool { false }   // no model file yet

    func generate(instructions: String, prompt: String) async throws -> String {
        throw BackendError.modelNotDownloaded
    }

    func reset() async { }
}
```

This compiles today and lets you wire the Settings backend-picker UI without a model file on disk. The picker grays out the LFM2 / Qwen rows with "Download to enable."

### Swap-to-real diff (LFM2 backend)

When the `LFM2.5-1.2B-4bit-MLX` weights are present in `Documents/Models/`:

```swift
import AnyLanguageModel    // ← add to Package.swift

actor MLXBackend: TCCCLLMBackend {
    nonisolated let displayName: String
    private let modelDirectory: URL
    private var session: LanguageModelSession?

    init(displayName: String, modelDirectory: URL) {
        self.displayName = displayName
        self.modelDirectory = modelDirectory
    }

    func isReady() async -> Bool {
        FileManager.default.fileExists(atPath: modelDirectory.path)
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        let session = try await ensureSession(instructions: instructions)
        do {
            let response = try await session.respond { Prompt(prompt) }
            return response.content
        } catch {
            throw BackendError.generationFailed(error.localizedDescription)
        }
    }

    func reset() async { session = nil }

    private func ensureSession(instructions: String) async throws -> LanguageModelSession {
        if let session { return session }
        guard await isReady() else { throw BackendError.modelNotDownloaded }

        let model = MLXLanguageModel(modelDirectory: modelDirectory)
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(instructions)
        )
        self.session = session
        return session
    }
}
```

The `MLXLanguageModel` initializer accepts a local directory (so we don't have to hit `huggingface_hub` at runtime — once downloaded it runs offline), wraps the MLX-Swift loader, and exposes the same `respond(to:)` API that Apple's `LanguageModelSession` does. **The four generator classes change zero lines** — they call `model.generate(prompt:)` either way; only the model factory in `AppState` switches which backend it instantiates.

For a `LlamaCppBackend` the diff is identical except `MLXLanguageModel` becomes `LlamaLanguageModel(modelPath: ggufURL)`.

### Settings UI tie-in

Add a `Backend` enum:

```swift
enum LLMBackendChoice: String, CaseIterable {
    case appleFoundation = "Apple Foundation Models"
    case lfm2_1_2b_mlx   = "LFM2.5-1.2B (MLX)"
    case qwen3_1_7b_mlx  = "Qwen 3 1.7B (MLX)"
    case lfm2_1_2b_gguf  = "LFM2.5-1.2B (llama.cpp)"
}
```

Settings overlay shows the choice with a download button next to any non-installed backend. Default remains `appleFoundation`. The choice is read by `AppState.makeLanguageModel(for:)` when constructing each generator's backend.

---

## 6. Recommendation

### First commit: LFM2.5-1.2B-Instruct-MLX-4bit

**Why LFM2 over Qwen 3:**

1. **License is good enough** (Apache-2.0-derivative with one revenue clause; no AUP) and **arguably better suited** to the kind of "we'll never know if Liquid is upset by this" anxiety than Llama's explicit prohibition. Apache 2.0 (Qwen) is technically cleaner; LFM Open License v1.0 is not OSI-approved but is in practice equivalently permissive for our use case.
2. **Smaller** (660 MB at MLX-4bit vs Qwen's 968 MB) — important for the first-launch download UX.
3. **Faster** on iPhone 17 Pro (59.7 tok/s vs 39.5).
4. **Better at IFEval** (74.89 vs 73.98) — the metric that controls TranscriptCleaner reliability.
5. **Smaller KV cache** thanks to the hybrid architecture — only 6 attention layers vs Qwen's 28 — leaving more memory headroom for Speech and the SwiftUI app to coexist.

**Why Qwen 3 1.7B is the contingency:** it has the cleanest license (straight Apache-2.0), the best raw knowledge (MMLU 59.11 vs 55.23), and is the most widely-supported model in third-party iOS demos. If LFM2's hybrid architecture trips on an MLX-LM bug or AnyLanguageModel handles it badly, Qwen 3 is a one-line drop-in replacement.

### Bundle vs first-launch download

**Download, don't bundle.** Reasoning:

- 660 MB MLX 4-bit is too large for an IPA the user re-signs every 7 days on a free Apple ID. SideStore re-sign over Wi-Fi takes ~30 s for a 50 MB IPA; a 660 MB IPA would push toward 5+ minutes per refresh, which would actively discourage running the app.
- A one-time HTTPS GET against a user-controlled URL (preferred: a static asset at a GitHub release the user controls; alternative: HF direct) is acceptable under RF Ghost provided it is **explicitly user-confirmed**, behind a single in-app button, with an audible/visible "Network access during download" warning, and the app's network stack is **otherwise** rejected at compile time (no `URLSession` outside `ModelDownloader.swift`, enforced via grep test).
- Verify SHA-256 against a hash baked into the binary before any inference touches the file. This protects against a rogue server returning a tampered model.
- After the single download, the network stack goes silent for the lifetime of the install. This restores RF Ghost.

Concrete first-launch flow:

```
User taps Settings → "Use LFM2.5-1.2B (slower, no Apple Intelligence required)"
↓
"This requires downloading 660 MB. Wi-Fi will be used once. After download,
the app returns to RF-silent operation. Continue?"
↓ [Continue]
[Wi-Fi check] [URLSession download → progress bar → SHA-256 verify]
↓
"Download complete. RF Ghost re-engaged." [OK]
↓
Backend is now selectable. Apple Foundation Models remains the default until
the user manually switches.
```

### Quality validation — how the operator knows it's good enough to switch

Before promoting LFM2 from "available, opt-in" to "recommended" or "default," run a deterministic four-task fixture sweep:

1. **Bundle the four scenario fixtures** (`tests/scenarios/*.txt` from the Python prototype) and the canonical "expected output" for each generator that we already have for Apple Foundation Models.
2. **Side-by-side diff view** in Settings → Diagnostics → "Compare Backends." User picks a fixture, the app runs the same prompt against Apple Foundation Models and the LFM2 backend, displays both outputs in a two-column view with a third column showing the engine-state ground truth.
3. **Validators** (a port of the Python prototype's `validate_medevac_against_state` and `validate_zmist_against_state`, see `RESEARCH_LLAMA32B.md` §7) flag any field hallucination — wrong callsign, missing patient ID, fabricated drug administration. Each candidate output gets a pass/warn/reject score.
4. **Operator decision rule:** switch the default to LFM2 when, on all four fixtures, the validators report zero `reject`-severity findings on three consecutive runs and the operator subjectively rates the output ≥ 4/5 on a Settings → Diagnostics → "Rate this output" Likert. Otherwise keep Apple Foundation Models as default and treat LFM2 as "for cleaner only" (the use case where Apple's safety filters most reliably refuse).

This is essentially the same evaluation framework the Python prototype uses to gate any LLM-generated report from showing on screen — extended one layer up to gate which model gets selected in the first place.

---

## Honest uncertainties

- **The LFM2 Open License's real-world enforceability for medical / military use is untested.** No one has ever litigated it (the license is from 2024–2025). I am 95 % confident a reasonable reading says we're fine. I am 100 % confident it doesn't *contain* the words that would forbid us. If you want to be paranoid: write Liquid's license team (`legal@liquid.ai`) a one-paragraph "we are a single-medic personal project that includes military-context language; anything we should know?" inquiry, archive the response. That's a free way to get a paper trail.
- **Qwen 3 1.7B benchmarks for the *Instruct* variant are scattered across the technical report, EvalScope, and third-party scrapes** — no single canonical table. The numbers I've cited are consistent across sources but not all from the same evaluation harness. Treat ±2 points as the noise floor.
- **iPhone 17 Pro benchmarks for Qwen 3 1.7B at long context (>4 k) are not in Takkar's published data.** The 39.5 tok/s is medium-prompt p50. KV-cache growth on the full 32 k context could push the 1.7B closer to its memory limit; field-test before committing.
- **The "2× faster than Qwen 3" claim from Liquid is on CPU**, not on iPhone GPU (where MLX runs). Takkar's numbers show LFM2.5 1.2B beats Qwen 3 1.7B by ~50 % on iPhone — material but less than 2×. The architectural advantage is real but partly diluted by Apple Silicon's GPU being good at attention.
- **Apple Foundation Models on iPhone 17 Pro is empirically faster than either candidate**, because it hits the ANE directly and the MLX path doesn't. If quality is acceptable and the app's RF-silent guarantees are intact (they are; Apple's model is fully on-device), the open-weights candidates are upgrades only for the **TranscriptCleaner** (where Apple's safety filters refuse clinical/military phrasings) and possibly the **EncounterNarrative** (where prose quality of a non-Apple model may feel more natural).

---

## Sources

- [Qwen3-1.7B model card (HF)](https://huggingface.co/Qwen/Qwen3-1.7B)
- [Qwen3-1.7B-GGUF (HF, official)](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF)
- [mlx-community/Qwen3-1.7B-4bit](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit)
- [Qwen 3 Technical Report — arXiv 2505.09388](https://arxiv.org/abs/2505.09388)
- [Qwen 3 release blog](https://qwenlm.github.io/blog/qwen3/)
- [LFM2.5-1.2B-Instruct model card (HF)](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct)
- [LFM2-1.2B-GGUF (HF, official)](https://huggingface.co/LiquidAI/LFM2-1.2B-GGUF)
- [mlx-community/LFM2-1.2B-4bit](https://huggingface.co/mlx-community/LFM2-1.2B-4bit)
- [LFM Open License v1.0 (Liquid AI)](https://www.liquid.ai/lfm-license)
- [LFM Open License — model license docs](https://docs.liquid.ai/lfm/getting-started/model-license)
- [Liquid AI — LFM2 announcement blog](https://www.liquid.ai/blog/liquid-foundation-models-v2-our-second-series-of-generative-ai-models)
- [Liquid AI — llama.cpp deployment guide](https://docs.liquid.ai/deployment/on-device/llama-cpp)
- [llama.cpp PR #14620 — LFM2 architecture support (merged)](https://github.com/ggml-org/llama.cpp/pull/14620)
- [llama.cpp issue #22287 — LFM2-MoE architecture (different model)](https://github.com/ggml-org/llama.cpp/issues/22287)
- [Ricky Takkar — How Fast Are On-Device LLMs on iPhone 17 Pro and iPad Pro? (8 Feb 2026)](https://rickytakkar.com/blog_russet_mlx_benchmark.html)
- [mattt/AnyLanguageModel](https://github.com/mattt/AnyLanguageModel)
- [HuggingFace blog — Introducing AnyLanguageModel](https://huggingface.co/blog/anylanguagemodel)
- [tattn/LocalLLMClient](https://github.com/tattn/LocalLLMClient)
- [ml-explore/mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)
- [MLX memory usage issue — ml-explore/mlx-examples #1025](https://github.com/ml-explore/mlx-examples/issues/1025)
- [Apple Developer — com.apple.developer.kernel.increased-memory-limit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)
- [Apple Developer — os_proc_available_memory](https://developer.apple.com/documentation/os/3191911-os_proc_available_memory)
- [WWDC25 — Explore large language models on Apple silicon with MLX](https://developer.apple.com/videos/play/wwdc2025/298/)
- [Distil Labs — small-LLM benchmark survey](https://www.distillabs.ai/blog/we-benchmarked-12-small-language-models-across-8-tasks-to-find-the-best-base-model-for-fine-tuning/)
- [EvalScope — Qwen3 evaluation tutorial](https://evalscope.readthedocs.io/en/latest/best_practice/qwen3.html)
- [Empirical Study of Qwen3 Quantization — arXiv 2505.02214](https://arxiv.org/html/2505.02214v1)
- [LFM Open License community thread (caveat re: not-OSI-approved)](https://huggingface.co/LiquidAI/LFM2-2.6B-Exp-GGUF/discussions/3)
- [Predecessor research — RESEARCH_LLAMA32B.md](RESEARCH_LLAMA32B.md)
