# Apple Foundation Models — Agentic Harness Research (2026-07-02)

Compiled for the 2026-07-02 sprint
(`docs/superpowers/specs/2026-07-02-transcription-and-fm-harness-sprint-design.md`).
Context: deterministic event-sourced engine; LLM proposes, never mutates.

---

## 1. Core API

- **`SystemLanguageModel`** (iOS 26.0+, Observable, Sendable) —
  `SystemLanguageModel.default` or `init(useCase:guardrails:)`. Availability:
  `.available`, `.unavailable(.deviceNotEligible /
  .appleIntelligenceNotEnabled / .modelNotReady)` — each deserves a distinct
  fallback (our deterministic extractors are the floor).
  https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
  Known trap: Siri-language/locale mismatch can block asset download while
  availability reads `.available` (FB19844387).
- **`LanguageModelSession`** — `init(model:tools:instructions:)` or rehydrate
  via `init(model:tools:transcript:)`. **Instructions outrank prompts by
  training** ("obey instructions over prompts… protects against prompt
  injection, but by no means bullet proof" — WWDC25 286). **Never interpolate
  ASR text into instructions** — untrusted input goes in prompts only.
  `prewarm(promptPrefix:)` removes the observed 1–2 s cold start.
  `isResponding` — concurrent `respond` throws `.concurrentRequests`; serialize.
  https://developer.apple.com/documentation/foundationmodels/languagemodelsession
- **Context window: 4,096 tokens per session, all-inclusive** (instructions,
  prompts, tool definitions/inputs/outputs, schemas, responses accumulate) —
  TN3193: https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
  ~3–4 chars/token English. iOS 26.4 adds `contextSize` + `tokenCount(for:)` +
  `usage`; the WWDC26 model on OS 27 reports 8,192.
- **Overflow:** `GenerationError.exceededContextWindowSize` kills the session;
  Apple's pattern: new session from condensed transcript
  (`Transcript(entries: [first, last])`) or summarize-and-reseed. Full error
  cases: `assetsUnavailable`, `decodingFailure`, `exceededContextWindowSize`,
  `guardrailViolation`, `rateLimited`, `refusal`, `concurrentRequests`,
  `unsupportedGuide`, `unsupportedLanguageOrLocale`. NOTE: the enum is
  deprecated in Xcode 27 (→ `LanguageModelError`) — isolate error mapping in
  one adapter type.
- **`GenerationOptions(samplingMode:temperature:maximumResponseTokens:)`**;
  `.greedy` = deterministic *within one OS model version only* (WWDC25 301:
  OS updates change outputs even under greedy) — the deterministic validator
  remains the real invariant. Strict `maximumResponseTokens` "can lead to…
  malformed results."
- **Streaming:** `streamResponse` yields **snapshots, not deltas** — the
  `@Generable` macro emits a `PartiallyGenerated` all-optional mirror type.
- **Rate limits:** none in foreground (absent device load); background has a
  budget → `.rateLimited`. Never call FM while backgrounded.

## 2. Guided generation

- `@Generable` on structs/enums → compile-time `GenerationSchema`;
  `@Guide(description:)` + constraints (`.range`, `.count`, `.anyOf`, regex
  patterns for strings). Nested/recursive types compose.
- **Constrained decoding guarantees structure** ("masking out the tokens that
  are not valid" — WWDC25 301): no invented fields, enums always from your
  cases, numbers within `.range`. It does NOT guarantee semantic truth —
  fabricated-but-well-formed values remain possible → evidence + validator
  gate. `decodingFailure` is a rare edge.
- `respond(generating: T.self, includeSchemaInPrompt:options:)` — set
  `includeSchemaInPrompt: false` only when the transcript already contains the
  schema.
- `DynamicGenerationSchema` builds schemas at runtime (validated via throwing
  `GenerationSchema(root:dependencies:)`; read with
  `generatedContent.value(_:forProperty:)`) — an option for generating
  per-rubric schemas from `dd1380_field_inventory.json` later.
- Best practices (TN3193): schemas small (screen space ≈ token use), `@Guide`
  short and only where needed, **enums over free strings** (also an Apple
  safety recommendation).

## 3. Tool calling

- `protocol Tool: Sendable` — `name`, `description`,
  `parameters: GenerationSchema` (derived from `Arguments: @Generable`),
  `call(arguments:) async throws -> Output: PromptRepresentable`.
  https://developer.apple.com/documentation/foundationmodels/tool
- **The framework drives the loop inside one `respond` call**; parallel calls
  possible (make `call` thread-safe); no max-iteration knob on iOS 26 (OS 27
  adds a beta `ToolCallingMode`). Tool calls consume context. Tools are fixed
  per-session (OS 27 `DynamicProfile` fixes this).
- **Reliability on the 3B model:** structural argument hallucination is
  impossible (constrained decoding), but *behaviorally* the model sometimes
  never selects a registered tool; multi-step chains are weak; **combining
  root-level guided generation with tools suppressed tool use** in community
  testing; naming a tool in the prompt confused it. TN3193: **max 3–5 tools**,
  verb names, one-sentence descriptions, and: "In the cases where the model
  should always have information from a tool, run the tool directly before you
  call the model and integrate the tool's output to the prompt directly."
  → Our extraction lane inlines the state digest and registers no tools.

## 4. Guardrails / safety / acceptable use

- `SystemLanguageModel.Guardrails`: `.default` (input+output checks; targets
  self-harm/violence/adult) and `.permissiveContentTransformations` — **but
  permissive mode only applies to plain-String generation; guided generation
  always runs default guardrails.** Inner-model refusals (`.refusal`) exist
  regardless. Combat-trauma narration sits in the violence-adjacent
  false-positive zone; iOS 26.4 reduced false positives. Mitigations: clinical
  register, documentation framing in instructions, enum-constrained outputs,
  catch-and-fallback to deterministic extractors, dev-mode
  `logFeedbackAttachment`.
  https://developer.apple.com/documentation/foundationmodels/improving-safety-from-generative-model-output
- **Acceptable use** prohibits unsupervised consequential decisions in medical
  domains. Our shape — proposal → deterministic validator → operator confirm →
  engine sole-writer — is the required human-supervision posture; document at
  the service boundary.
  https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/
- `SystemLanguageModel(useCase: .contentTagging)` — built-in adapter for
  tagging/entity extraction; integrates with guided generation; worth
  benchmarking for finding/intervention tagging.

## 5. Custom adapters — ruled out

Rank-32 LoRA toolkit (Python 3.11+, ≥32 GB Apple silicon — the M4 Max
qualifies for *training*), ~160 MB `.fmadapter`. Blockers: production requires
the `com.apple.developer.foundation-model-adapter` entitlement via an Apple
Developer Program Account Holder (SideStore distribution rules it out);
adapters break on every OS model update; Apple recommends Background Assets
(conflicts with RF Ghost). Apple's own advice: exhaust prompt engineering +
tool calling first. https://developer.apple.com/apple-intelligence/foundation-models-adapter/

## 6. Apple's recommended agentic shape

Model: ~3B params @ 2-bit; "optimized for summarization, extraction,
classification"; "not designed for world knowledge or advanced reasoning";
"device scale models require tasks to be broken down into smaller pieces."
Pattern: **many small focused requests orchestrated by deterministic code**,
not one autonomous loop. Latency on A19 Pro-class: 1–2 s cold start (prewarm
removes), TTFT ~0.5–2 s, ~10–30 tok/s; profile with the Foundation Models
Instruments template. iOS 27 (plan, don't depend): 8K context,
`ContextOptions(reasoningLevel:)`, automatic transcript condensation,
`DynamicProfile`, image attachments, built-in OCR/Barcode/Spotlight tools,
`LanguageModel` protocol for third-party backends.

Key sessions: WWDC25 286 (Meet), 301 (Deep dive), 259 (code-along travel
planner — canonical tools+streaming sample), TN3193, WWDC26 241.

## 7. Recommended harness shape (as adopted by the sprint spec §7)

- **Stateless micro-sessions**: fresh session per settled batch; prompt =
  deterministic ~300-token state digest + new chunk batch; prewarmed template
  keeps TTFT sub-second; no accumulation → no condensation → unbounded
  encounter length.
- **Inline the digest; no tools in the extraction lane** (guided generation
  suppresses tool use; digest is always needed → TN3193 says inline it).
  Optional 2-tool read-only diagnostic lane later (`getVitalsTrend`,
  `getEventsSince`) — tools query the engine, never mutate: `Tool.call` has no
  engine-write surface, preserving the invariant mechanically.
- **`@Generable FMCandidatePatch`**: typed vitals (`@Guide(.range)` physiologic
  bounds), interventions/findings as rubric-derived enums, per-proposal
  `evidence: String` (verbatim supporting words). Validator gate: evidence
  fuzzy-substring vs source chunk (anti-fabrication), physiologic plausibility,
  idempotence vs state → review queue → operator accept → FieldRouter → engine.
- **Report lane**: fresh session per 9-line/ZMIST/narrative draft generating
  existing structures; `MedevacValidator`/`ZMISTValidator` + 40 % drift
  fallback unchanged.
- **Token budget** (~3.5 chars/token): instructions ≈400 + digest ≈300 +
  chunks ≈250 + schema ≈600 + output ≈300 ≈ 1,850 of 4,096. On overflow:
  digest-only retry once, then deterministic fallback.
- **Error adapter** (one type, since `GenerationError` is deprecated in
  Xcode 27): overflow → shrink/retry → fallback; guardrail/refusal → fallback +
  feedback log; decoding → one retry → fallback; concurrent → actor-serialize;
  assets → status badge + deterministic-only mode.
