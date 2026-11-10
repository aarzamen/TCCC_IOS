# Llama 3.2 3B on iPhone 17 Pro for TCCC.ai — Feasibility Research

**Date:** 2026-05-05
**Target device:** iPhone 17 Pro, A19 Pro, 12 GB unified RAM, iOS 26.2
**Goal:** Replace Apple Foundation Models with Llama 3.2 3B for radio-script / narrative / ZMIST / TranscriptCleaner use cases — fully on-device, RF-silent.
**Distribution:** SideStore (no Apple Developer Program).

---

## TL;DR

**This is technically feasible but lands in a yellow zone, not a green one.** The single most important finding: the public benchmark of Llama 3.2 3B on the iPhone 17 Pro (Ricky Takkar, March 2026) reports that the 3B model **could not be loaded** because it exceeded the per-app memory ceiling iOS imposes via jetsam — the practical foreground budget on a 12 GB device sits at roughly 50% of total, i.e. ~6 GB, and MLX 4-bit weights alone plus a 4–16k KV cache push close to or past that limit. Llama 3.2 1B at 4-bit (713 MB on disk) ran cleanly at **~58 tok/s** with a **~253 ms time-to-first-token**, and is the safer target if quality is acceptable. There is also a real **license problem**: the Llama 3.2 Acceptable Use Policy explicitly forbids "military, warfare" applications and "unauthorized or unlicensed practice of any profession including… medical/health." TCCC.ai sits on both forks of that prohibition. A serious deployment would need either a Meta authorization, a non-Llama base model (Qwen 3, Phi 4, Gemma 3 — most are also restrictive but worth checking case-by-case), or acceptance that this is a personal research artifact never distributed.

**Recommendation in one line:** keep Apple Foundation Models as the default backend, add an `AnyLanguageModel`-style abstraction so a Qwen-3 1.7B or Llama 3.2 1B 4-bit MLX backend can be tried as a side-by-side option, and treat Llama 3.2 3B as an "if/when the iPhone 18 Pro ships with more RAM and a higher jetsam budget" item.

---

## 1. Llama 3.2 3B — variants and license

Llama 3.2 was released **2024-09-25** and includes 1B and 3B text models (and 11B / 90B vision variants, irrelevant here). For the 3B:

- **Base** — `meta-llama/Llama-3.2-3B`, no instruction tuning. Useless for our prompts.
- **Instruct** — `meta-llama/Llama-3.2-3B-Instruct`. This is what you want.
- **Tokenizer:** Llama 3 tokenizer, 128k vocab.
- **Context window:** 128k tokens (same as Llama 3.1).
- **Architecture:** decoder-only transformer, 28 layers, 3,072 hidden, 24 heads, 8 KV heads (GQA).

### License — material concern

The **Llama 3.2 Community License** has two clauses that hit TCCC.ai directly. From the Acceptable Use Policy at `llama.com/llama3_2/use-policy/`:

1. **Military / warfare:** "You agree not to use… in any way that violates any applicable law or regulation… related to military, warfare, nuclear industries or applications…"
2. **Medical practice:** "You agree not to use… in connection with the unauthorized or unlicensed practice of any profession including, but not limited to, financial, legal, **medical/health**, or related professional practices."

The 700M-MAU license-trigger clause does not bite (this is a single-user prototype), but the AUP is binding regardless of scale. A combat-medic documentation app is a textbook case of both. The user is a licensed MD, which arguably defeats prong 2 for personal use, but prong 1 (military) is harder to argue around for an app whose stated purpose is field combat use.

**Practical read:** for a personal sideloaded build that is never distributed, the legal risk is low (Meta is not going to sue an MD using the model on their own iPhone), but the AUP would block App Store distribution and probably block any field-test or institutional pilot. If you ever want this to leave your own device, you need to pick a different base model. Qwen 3 (Apache-2.0) and Gemma 3 (Gemma license — also has a list of prohibited uses, but no explicit military clause) are the obvious replacements.

### 1B vs 3B quality

Public benchmarks from Meta and Hugging Face evaluations:

| Benchmark           | Llama 3.2 1B-Instruct | Llama 3.2 3B-Instruct |
|---------------------|-----------------------|-----------------------|
| IFEval (instruct)   | ~52                   | **77.4**              |
| MMLU 5-shot         | ~49                   | **63.4**              |
| BFCL V2 (tool use)  | 25.7                  | **67.0**              |

The IFEval gap is what matters for TranscriptCleaner — that task is pure instruction-following ("fix mishearings, do not paraphrase, do not summarize"). The 1B is markedly weaker at staying on-task. Tool-use (relevant if you ever add @Generable structured output) is a 2.6× gap. For the current four use cases, **3B is qualitatively better-suited**, but only if the device can hold it.

---

## 2. Quantization

GGUF file sizes for Llama 3.2 3B Instruct (Mungert/Llama-3.2-3B-Instruct-GGUF, Hugging Face):

| Quant   | Size      | Notes |
|---------|-----------|-------|
| Q4_K_M  | **2.02 GB** | The usual sweet spot. Per llama.cpp community benchmarks, ~+0.25 ppl over FP16 on 7B-class models; for 3B the hit is somewhat larger but still acceptable for instruction-following. |
| Q5_K_M  | **2.32 GB** | ~+0.04 ppl. Better quality at 0.3 GB cost. |
| Q6_K    | 3.11 GB   | Near-lossless, but eats almost a third more memory than Q4_K_M. |
| Q8_0    | 3.79 GB   | Effectively lossless (+0.01 ppl). Way too big for iPhone. |
| F16     | 2.48 GB   | (3B is small enough that F16 is barely larger than Q5_K_M — but at the cost of compute, not weight load.) |

MLX has its own quant scheme — typically `mlx-community/Llama-3.2-3B-Instruct-4bit` is around 1.8 GB on disk but **uses noticeably more runtime memory** than the equivalent GGUF (one user report: 15 GB MLX 4-bit @ 16k context vs 3.7 GB GGUF Q4 — see ml-explore/mlx-examples #1025). This matters: MLX KV cache is allocated up-front to the maximum context, whereas llama.cpp grows it incrementally.

**Recommendation: Q4_K_M (GGUF) is the right target.** Q5_K_M is a tempting upgrade but the extra 300 MB of resident memory eats into the tight headroom. MLX 4-bit is faster on Apple Silicon when it fits, but on iPhone where the jetsam ceiling is hard, GGUF Q4_K_M's smaller, demand-paged footprint is the safer engineering choice.

---

## 3. iOS runtimes

### MLX-Swift (`ml-explore/mlx-swift` + `mlx-swift-examples`)

- Native Apple framework, GPU + ANE-aware, fastest decode on Apple Silicon when models fit.
- `LLMEval` and `MLXChatExample` in `mlx-swift-examples` both run on iOS device builds (sims don't support Metal features they need).
- Model loading downloads from Hugging Face on first run (the `Hub` Swift package). For RF Ghost compliance you'd need to vendor a one-time downloader against a URL you control, or bundle the weights.
- Active development, official Apple-blessed path (WWDC25 declared MLX the "preferred framework for LLM inference on Apple Silicon").
- **Catch:** MLX's KV cache memory model is greedier than llama.cpp. On iPhone the 3B will not run reliably; the 1B does.

### llama.cpp Swift bindings (`ggml-org/llama.cpp` Swift Package)

- Older, more battle-tested, the GGUF reference implementation.
- Smaller incremental memory footprint, demand-paged weights via mmap, KV cache grows as needed.
- Slower than MLX on Apple Silicon for the same model (no ANE access; uses Metal compute).
- **iPhone 16 Pro (A18 Pro) reports for Llama 3.2 3B Q4_K_M cluster around 20–30 tok/s decode** with Llama.cpp; the iPhone 17 Pro should be modestly higher when it fits at all.
- The official `llama` Swift Package builds and links cleanly into a SwiftUI iOS target.

### CoreML (`coreml-llama` etc.)

- ANE-first, in theory the fastest and most power-efficient path.
- Narrow model support, conversion is fragile, KV cache management is awkward.
- Apple's own `swift-transformers` work has been shifting toward MLX rather than CoreML for LLMs.
- **Skip.** Not worth the conversion pain unless ANE power efficiency is the deciding factor.

### LocalLLMClient (`tattn/LocalLLMClient`) — wrapper over both

- Single Swift Package that supports llama.cpp, MLX, and Foundation Models behind one API.
- iOS 17+, includes a `FileDownloader` for Hugging Face weights.
- Status: pre-1.0, "experimental, API may change."

### AnyLanguageModel (`mattt/AnyLanguageModel` / `huggingface/AnyLanguageModel`) — drop-in for Apple's framework

- This is the cleanest fit for the existing TCCC.ai codebase.
- API-compatible with `FoundationModels`: same `LanguageModelSession`, same `respond(to:)` shape.
- Backends: Core ML, MLX, llama.cpp, Ollama, plus cloud providers (which we'd never use).
- Swap example:

  ```swift
  // Today (in TCCCLanguageModel.swift):
  let session = LanguageModelSession(instructions: instructions)

  // After swap:
  let model = LlamaLanguageModel(modelPath: gguPath)   // or MLXLanguageModel(modelId: ...)
  let session = LanguageModelSession(model: model, instructions: instructions)
  ```

- Requires Swift 6.1+ (we are on 6.2.3, fine), still pre-1.0.

**Pick:** `AnyLanguageModel` as the abstraction layer, `llama.cpp` backend for Llama-class models, with a config switch to fall back to MLX for 1B (where MLX is faster and fits).

---

## 4. Throughput expectations

Best public iPhone 17 Pro reference data — Ricky Takkar, "How Fast Are On-Device LLMs on iPhone 17 Pro and iPad Pro?" (March 2026, MLX runtime):

| Model                        | TTFT (ms) | Decode (tok/s) | Status on iPhone 17 Pro |
|------------------------------|-----------|----------------|--------------------------|
| Llama 3.2 1B 4-bit MLX       | ~253      | **~58**         | Runs, tight IQR, reliable |
| LFM2.5 1.2B 4-bit            | —         | ~60             | Runs |
| Qwen 3 0.6B                  | —         | ~70             | Runs |
| **Llama 3.2 3B 4-bit MLX**   | —         | —               | **Could not load — exceeded jetsam limit** |
| Qwen 3 4B 4-bit              | —         | —               | Same — could not load |

llama.cpp historical numbers on similar Apple Silicon (decode):
- M4 Max (LLaMA 7B Q4_0) ≈ 83 tok/s decode, 886 tok/s prefill (llama.cpp PR #4167)
- iPhone 16 Pro (A18 Pro), Llama 3.2 3B Q4_K_M, llama.cpp ≈ **20–30 tok/s** decode (community reports, less rigorous than the MLX numbers above)

**For TCCC.ai's actual workloads** (~500 tokens prompt in, ~100 tokens out):

- Cleaner: ~500 prompt tokens, ~500 output tokens (cleaned transcript echoed back). At 30 tok/s = ~17 s wall-clock. That's a noticeable wait.
- Radio script: ~150 prompt, ~120 output. ~4 s.
- Encounter narrative: ~300 prompt, ~70 output. ~2.5 s.
- ZMIST: ~400 prompt, ~150 output. ~5 s.

For comparison, Apple Foundation Models on the same device runs all four in well under 2 seconds because it's hitting the ANE directly. **Llama 3.2 3B will be a noticeably slower experience** even if the memory issue is solved. Llama 3.2 1B will be in the same speed ballpark as Apple's model.

---

## 5. Memory footprint — the real blocker

iOS jetsam math on a 12 GB device:

- iOS reserves ~2–3 GB for system processes and graphics surfaces.
- The standard foreground-app limit lands somewhere between **5 and 6 GB before jetsam fires**.
- The `com.apple.developer.kernel.increased-memory-limit` entitlement raises this on supported devices, typically to ~75% of physical RAM (so ~9 GB). **AltStore/SideStore can carry this entitlement** — version 2.2+ supports sideloading apps that declare it. You'd just add it to `project.yml` and re-sign.
- The runtime API is `os_proc_available_memory()` — call it before loading the model, check you have at least 2.5 GB of headroom over the GGUF size, and refuse to load if not.

For Llama 3.2 3B Q4_K_M:
- Weights resident: ~2.0 GB
- KV cache @ 4k context, 28 layers × 8 KV heads × 128 dim × 2 (K+V) × FP16 ≈ **~230 MB**
- KV cache @ 16k context: ~920 MB
- llama.cpp scratch buffers, compute graph, tokenizer: ~200–400 MB
- The TCCC.ai app itself: SwiftUI + Speech recognizer + audio buffers + photo library bridge + Canvas rendering ≈ **600–900 MB resident** in active use

Realistic total resident at inference time: **~3.5 GB at 4k context, ~4.2 GB at 16k.**

That fits under the entitled ceiling (~9 GB) but is **uncomfortably close to the unentitled ~6 GB ceiling** if the OS is also under pressure (Speech is greedy, the Canvas backbuffer for the ECG view is non-trivial, Foundation Models if also loaded carries its own ~2 GB).

**Background behavior:** when the app backgrounds, iOS will compress and evict. The model file itself (mmap'd) gets paged out cleanly; the live KV cache and compute buffers get compressed but may be discarded if the app stays backgrounded long enough. Plan to detect `UIApplication.willResignActiveNotification` and explicitly free the inference state, then reload on `didBecomeActive` (slow first inference but no crashes).

**Bottom line:** with the increased-memory-limit entitlement and 4k context, **Llama 3.2 3B Q4_K_M is feasible**. Without the entitlement, it's a coin flip per launch. Llama 3.2 1B 4-bit is comfortable in both regimes.

---

## 6. System-prompt strategy

The current `TranscriptCleaner.systemInstructions` is well-written for Apple's model. Llama 3.2 will need adjustments:

```
You are a transcript cleaner. You receive ASR output of a combat medic
narrating casualty care. You output the same transcript with mishearings
fixed.

Rules — follow exactly:
1. Output one line per input line. Same count, same order, same timestamps,
   same speakers.
2. Format every output line as: [HH:MM] SPEAKER: text
3. Fix only obvious mishearings. Examples:
   - "tea-x-a", "tee ex ay" → "TXA"
   - "moxifloxin" → "moxifloxacin"
   - "nine line" → "9-Line"
   - "med evac", "medi vac" → "MEDEVAC"
   - "femer" → "femur"; "thye" → "thigh"
4. Do NOT paraphrase. Do NOT summarize. Do NOT add commentary.
5. Do NOT change words you are unsure about — leave them unchanged.
6. Do NOT add a preface, header, or trailing notes. No markdown.

Output the cleaned transcript and nothing else. Stop after the last line.
```

**Llama failure modes to expect:**

- **Over-correction.** Llama models like to "improve" text they consider awkward. The "Do NOT paraphrase" rule needs to appear twice and ideally be reinforced with one or two few-shot examples that show preserved-but-clunky text.
- **Summarization drift.** If the transcript is long, Llama may collapse multiple lines into one. The "same count, same order" rule plus a parsing assertion in `TranscriptCleaner.merge` (which already falls back to originals when line counts mismatch) handles this.
- **Markdown injection.** Llama trained on a lot of markdown. It will sometimes wrap output in ``` fences. The output parser should strip leading/trailing code fences as a defensive step.
- **Refusals.** Llama-3.2-Instruct has guardrails around "military" content. A medic dictating "GSW to the femur, applied tourniquet" might trigger a refusal. Watch for outputs starting with "I cannot…" or "I'm not able to…" and treat those as failures (fall back to original).
- **Apologetic preambles.** "Sure, here's the cleaned transcript:" or "I've corrected the following mishearings:" — strip with a regex on the first line.

For the **RadioScriptGenerator**, the system prompt is already strong. Llama needs the same anti-preamble guardrails. The phonetic-alphabet rule will work better with one inline example.

For the **EncounterNarrativeGenerator** and **ZMISTNarrativeGenerator**, Llama 3.2 3B is genuinely a better writer than the Apple model — more natural prose, less formulaic. This is where the upgrade pays off most clearly, *if* you accept the latency cost.

---

## 7. Validator workflow

The Python prototype's `validate_medevac_against_state` and `validate_zmist_against_state` are exactly the right pattern — Llama is meaningfully more prone to fabrication than Apple's heavily-RLHF'd Foundation Model. Sketch:

```swift
struct LLMValidator {
    enum Severity { case ignore, warn, reject }
    struct Finding { let severity: Severity; let message: String }

    static func validateRadioScript(
        _ script: String,
        against form: NineLineForm
    ) -> [Finding] {
        var findings: [Finding] = []

        // Hard checks: every Line N value from the form must appear (verbatim
        // or as a phonetic substitution) somewhere in the script.
        for entry in form.entries {
            if !script.contains(entry.value)
                && !script.contains(phoneticize(entry.value)) {
                findings.append(.init(severity: .warn,
                    message: "Line \(entry.number) value missing from script"))
            }
        }

        // Hallucination checks: the script must not contain a "Line 10" or
        // "Line 11", must not invent a callsign different from the one passed
        // in, must not include an unsolicited timestamp, etc.
        if script.range(of: #"\bLine 1[0-9]\b"#, options: .regularExpression) != nil {
            findings.append(.init(severity: .reject, message: "Hallucinated Line 10+"))
        }

        return findings
    }
}
```

Integration in the generator:

```swift
func generate(from form: NineLineForm, ...) async throws -> String {
    for attempt in 0..<3 {
        let candidate = try await model.generate(prompt: ...)
        let findings = LLMValidator.validateRadioScript(candidate, against: form)
        if !findings.contains(where: { $0.severity == .reject }) {
            return candidate
        }
        // Add the finding to the next prompt as a corrective instruction
    }
    // Last resort: deterministic template fallback (the same path that
    // rendered radio script before SLM v1).
    return DeterministicRadioScript.render(form)
}
```

The Python-prototype validators in `src/reports.py` should be ported wholesale to a `TCCCKit/Sources/TCCCReports/Validators.swift` and unit-tested against the existing fixtures before any LLM-generated output ever shows on screen.

---

## 8. Integration plan — `LlamaLanguageModel` actor

Mirror the existing `TCCCLanguageModel` API exactly so the four feature classes (RadioScriptGenerator, EncounterNarrativeGenerator, ZMISTNarrativeGenerator, TranscriptCleaner) don't change. Add a runtime-selectable backend:

```swift
// TCCCLanguageModel becomes a protocol.
protocol TCCCLanguageModelProtocol: Actor {
    func generate(prompt: String) async throws -> String
    func reset()
}

// Existing class becomes:
actor AppleFoundationModel: TCCCLanguageModelProtocol { /* current impl */ }

// New backend:
actor LlamaLanguageModel: TCCCLanguageModelProtocol {
    private let llama: LLM        // wrapper around llama.cpp (via LocalLLMClient
                                  // or AnyLanguageModel)
    private let instructions: String
    private var contextHistory: [Message] = []

    init(modelPath: URL, instructions: String) async throws {
        self.instructions = instructions
        self.llama = try await LLM.load(path: modelPath,
            contextLength: 4096, gpuLayers: .all)
    }

    func generate(prompt: String) async throws -> String {
        contextHistory.append(.user(prompt))
        let messages = [.system(instructions)] + contextHistory
        let response = try await llama.chat(messages: messages,
            maxTokens: 512, temperature: 0.3)
        contextHistory.append(.assistant(response))
        return cleanOutput(response)   // strip preambles, code fences
    }

    func reset() { contextHistory.removeAll() }
}

// Generator factories check Settings.shared.preferredBackend and pick.
```

**Settings UI:** add a "Language model backend" picker to the Settings overlay (currently has theme picker, RF discipline, etc.). Options: `Apple Foundation Model (default)`, `Llama 3.2 1B (faster, smaller)`, `Llama 3.2 3B (slower, better)`. Show the model file's resident size and last-call latency next to each option.

**File layout:**
```
TCCC_IOS/Intelligence/
├── TCCCLanguageModelProtocol.swift   (new)
├── AppleFoundationModel.swift        (rename of TCCCLanguageModel.swift)
├── LlamaLanguageModel.swift          (new)
├── ModelDownloader.swift             (new — one-shot HTTPS GET, resumable)
└── … existing generators unchanged
```

---

## 9. Bundle size and distribution

A 2.0 GB GGUF inside a sideloaded IPA is large but not blocked:

- **SideStore** has no documented hard size cap. The free-Apple-ID 7-day re-sign loop works on the IPA whatever size — the only practical limit is your iPhone's free disk and how long the install / refresh transfer takes over Wi-Fi (~2 GB ≈ 2–3 minutes on local network).
- **Increased Memory Limit entitlement on a free Apple ID:** AltStore 2.2 / SideStore equivalent both support it now. You add the entitlement to `project.yml`, regenerate, and re-sign. No paid Developer Program needed.

**Recommendation: download-on-first-launch, not bundled.** Reasons:

1. Builds stay fast. A 2 GB IPA every iteration is painful.
2. Lets you swap models without rebuilding the app.
3. One-time HTTPS GET against a user-controlled URL (e.g., a static GitHub release asset, or a self-hosted file). After that single download, RF Ghost compliance is intact for the lifetime of the install.
4. Verify SHA-256 against a known-good value baked into the binary before letting any inference touch the file.

Concrete download flow:
- App launches, checks `Documents/Models/Llama-3.2-3B-Instruct-Q4_K_M.gguf`.
- If missing or hash-mismatched, prompt the medic: "Download Llama 3.2 (2.0 GB)? Will use Wi-Fi, then disable network access." → confirm → one-shot URLSession download.
- Once verified, the app's RF discipline assertions go back to "no network." This is the only allowed network call in the app's lifetime, behind an explicit user prompt, on first launch only.

---

## 10. Recommendation

### Honest assessment

Apple's Foundation Model is **already a good fit** for three of the four use cases. The only one where a swap to Llama is a clear win is the **TranscriptCleaner** — Apple's safety filters do refuse some clinical phrasings, and the cleaner is the most prompt-engineering-sensitive task. For radio script / narrative / ZMIST, the Apple model is faster, more reliable, doesn't have a license problem, and the quality is sufficient.

**The license problem is real.** Even setting aside the legal debate, the AUP makes it impossible to ever distribute this beyond your own device, which forecloses the most likely future of TCCC.ai (a real field-testable build). Switching to **Qwen 3 1.7B (Apache-2.0)** or a Gemma 3 variant is a strictly better path — better quality than Llama 3.2 1B, smaller than 3B, no military/medical AUP. I'd encourage you to run the same investigation against Qwen 3 1.7B before committing engineering effort to Llama specifically.

### Minimum viable integration (target by Friday)

1. Add `AnyLanguageModel` (or `LocalLLMClient`) as a Swift package dependency to `TCCC_IOS.xcodeproj` via `project.yml`.
2. Refactor `TCCCLanguageModel.swift` to the protocol pattern in §8. Existing generators keep working untouched.
3. Implement `LlamaLanguageModel` actor wrapping `LlamaLanguageModel` (the AnyLanguageModel one).
4. Add `Increased Memory Limit` capability to `project.yml`, regenerate.
5. Bundle a `Llama-3.2-1B-Instruct-Q4_K_M.gguf` (~810 MB) inside the IPA for the first run — small enough to ship in-bundle.
6. Add a Settings backend toggle. Default to Apple Foundation Model. Allow opting into Llama 1B for cleaner only.
7. Verify on-device throughput, latency, and that the app doesn't OOM under sustained use.

This is a 1-day spike that gets you a working A/B comparison without committing to the 3B path or the network-download flow.

### Full vision (target by month-end)

1. All of the above, plus:
2. **Switch base model to Qwen 3 1.7B-Instruct (Apache-2.0).** Re-test all four use cases. Likely outperforms Llama 3.2 1B and avoids the license issue.
3. Implement the validator layer in `TCCCKit/Sources/TCCCReports/Validators.swift`, port the Python prototype's `validate_medevac_against_state` and `validate_zmist_against_state` verbatim, unit-test against fixtures.
4. Implement download-on-first-launch flow with hash verification for any model that can't be bundled.
5. Make the Llama 3.2 3B path conditional: app only offers it on devices where `os_proc_available_memory()` returns ≥ 6 GB after model+system overhead.
6. Add SLM-loading status badges (already in `CLAUDE.md` "Future work — small wins").
7. Switch generators to `@Generable` structured output where AnyLanguageModel supports it — eliminates a class of parsing bugs.

### What I'd skip

- Building an in-house llama.cpp Swift wrapper. AnyLanguageModel and LocalLLMClient both exist and are good enough.
- CoreML conversion of Llama 3.2 3B. The conversion path is fragile and ANE access is not guaranteed to be faster in practice.
- Trying to keep both Apple Foundation Model and Llama 3.2 3B resident simultaneously. The memory budget does not support it. Pick one per session.

---

## Sources

- [Llama 3.2 3B Instruct on Hugging Face](https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct)
- [Llama 3.2 Acceptable Use Policy](https://www.llama.com/llama3_2/use-policy/)
- [Llama 3.2 Community License](https://www.llama.com/llama3_2/license/)
- [Mungert/Llama-3.2-3B-Instruct-GGUF (file sizes)](https://huggingface.co/Mungert/Llama-3.2-3B-Instruct-GGUF)
- [Ricky Takkar — How Fast Are On-Device LLMs on iPhone 17 Pro and iPad Pro?](https://rickytakkar.com/blog_russet_mlx_benchmark.html)
- [llama.cpp Apple Silicon performance discussion #4167](https://github.com/ggml-org/llama.cpp/discussions/4167)
- [Apple Developer — com.apple.developer.kernel.increased-memory-limit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)
- [Apple Developer — os_proc_available_memory](https://developer.apple.com/documentation/os/3191911-os_proc_available_memory)
- [Apple Developer Forums — Increased Memory Limit, Extended Virtual Addressing](https://developer.apple.com/forums/thread/777370)
- [ml-explore/mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)
- [Awni — Step-by-step LLM on iPhone with MLX Swift](https://gist.github.com/awni/fe4f96c21ead68e60191190cbc1c129b)
- [WWDC25 — Explore large language models on Apple silicon with MLX](https://developer.apple.com/videos/play/wwdc2025/298/)
- [tattn/LocalLLMClient](https://github.com/tattn/LocalLLMClient)
- [mattt/AnyLanguageModel](https://github.com/mattt/AnyLanguageModel)
- [HuggingFace blog — Introducing AnyLanguageModel](https://huggingface.co/blog/anylanguagemodel)
- [Medicine on the Edge — On-Device LLMs for Clinical Reasoning (arXiv 2502.08954)](https://arxiv.org/html/2502.08954v1)
- [Quantization evaluation on Llama-3.1-8B (arXiv 2601.14277)](https://arxiv.org/html/2601.14277v1)
- [Llama 3.2 Edge AI announcement (Meta AI)](https://ai.meta.com/blog/llama-3-2-connect-2024-vision-edge-mobile-devices/)
- [iPhone 17 Pro RAM specs (MacRumors)](https://www.macrumors.com/2025/09/09/iphone-17-pro-iphone-air-ram-amounts/)
- [AltStore 2.2 supports Increased Memory Limit entitlement](https://www.idownloadblog.com/2025/04/09/altstore-v2-2-beta-increased-memory-limit/)
- [SideStore FAQ](https://docs.sidestore.io/docs/faq)
- [MLX memory usage issue — ml-explore/mlx-examples #1025](https://github.com/ml-explore/mlx-examples/issues/1025)
