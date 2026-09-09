# Offline models for a new installation

The field-build path embeds a verified `OfflineModels` folder in the signed app.
It does not depend on an old app container or on a first-use download. The same
folder can be delivered over USB to `Documents/OfflineModels` for an existing
install. An ordinary source build without the build setting remains small and
reports missing assets honestly.

## Exact offered assets

| App backend | Pinned artifact | Revision |
|---|---|---|
| LFM2 1.2B | `mlx-community/LFM2-1.2B-4bit` | `3843e4ad0fcb8b7ed8a050908ac8f0bb5320d1bf` |
| Qwen 3 1.7B | `mlx-community/Qwen3-1.7B-4bit` | `3b1b1768f8f8cf8351c712464f906e86c2b8269e` |
| Granite text base | `mlx-community/granite-4.0-h-1b-base-4bit` | `c31361138fab2f0725a796f5fc50097a820759f1` |
| Granite Speech | `mlx-community/granite-4.0-1b-speech-5bit` | `371e6922faffba916e983e9c083049ad44536e94` |
| Kokoro TTS | `FluidInference/kokoro-82m-coreml`, 5s/15s CoreML, G2P and 54 voices | `acac8811a9acefe8bf7a5e3fcba99bd8fc50dcd6` |
| Parakeet EOU 120M | `FluidInference/parakeet-realtime-eou-120m-coreml`, **160ms** | `40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355` |

Apple Speech and Foundation Models are system services, not redistributable
weight folders in this package. Apple Intelligence must be enabled on a supported
device and complete its model download before going offline. System availability
and speech on-device capability are shown separately. Capability is not proof of
a successful live recognition session. [Apple setup requirements](https://support.apple.com/en-us/121115),
[Foundation Models availability guidance](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models),
[Speech capability API](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition).

## Prepare once on the installation Mac

Weights stay outside the source repository. This command downloads only public
model artifacts, verifies upstream LFS SHA-256/Git blob hashes, copies runtime
files and upstream notices, writes per-model SHA-256 manifests, then verifies the
complete output before publishing its directory. It never reads encounters,
recordings, device backups or credentials. It preserves an existing output and
requires a new output path for a revised package.

```bash
cd '/Users/ama/Documents/ChatGPT/TCCC project/ios-capture-reliability'
UV_CACHE_DIR=/private/tmp/tccc-uv-cache uv venv --python 3.12 /private/tmp/tccc-offline-tools
UV_CACHE_DIR=/private/tmp/tccc-uv-cache uv pip install \
  --python /private/tmp/tccc-offline-tools/bin/python huggingface_hub
/private/tmp/tccc-offline-tools/bin/python tools/stage_offline_models.py \
  --sources '/Users/ama/Documents/ChatGPT/TCCC project/private-model-staging-20260909/sources' \
  --output '/Users/ama/Documents/ChatGPT/TCCC project/private-model-staging-20260909/OfflineModels-complete' \
  --download
```

`--download` is explicit online preparation. Without it staging uses supplied
local files only; `--verify` is read-only and has no external dependencies or
network path. Full upstream license copies are fetched during online preparation;
model cards and license URLs/hashes remain with the package. The script stages
the three compiled Parakeet models plus vocabulary, not conversion scripts or
redundant `.mlpackage` training/export resources.

## Embed before signing

The app target's XcodeGen `preBuildScripts` entry runs:

```yaml
- name: Embed verified offline models
  script: bash "$SRCROOT/tools/embed_offline_models.sh"
  basedOnDependencyAnalysis: false
```

Build for the real iPhone with:

```bash
cd '/Users/ama/Documents/ChatGPT/TCCC project/ios-capture-reliability'
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS' -configuration Debug \
  -skipMacroValidation -allowProvisioningUpdates \
  -derivedDataPath /private/tmp/tccc-offline-device \
  TCCC_REQUIRE_OFFLINE_MODELS=YES \
  'TCCC_OFFLINE_MODELS_DIR=/Users/ama/Documents/ChatGPT/TCCC project/private-model-staging-20260909/OfflineModels-complete' \
  build
```

The pre-build step verifies the source hashes, copies the folder into the app's
resource root, and verifies the copied hashes before Xcode signs the bundle.
`TCCC_REQUIRE_OFFLINE_MODELS=YES` refuses to build without a supplied package.
There is no weight-fetching step in Xcode. Use a clean DerivedData path when
changing model revisions; verification rejects unexpected stale files.

Install the resulting signed app with the normal authorized Xcode/USB workflow.
Do not uninstall an existing clinical app to test this: use a separate test
device/container. In the new install, refresh Offline model preparation and
exercise each offered backend with synthetic input while radios are off. A
verified package and a successful build do not substitute for that device test.

For an existing device the same `OfflineModels` directory can be copied via
USB to its app's Documents folder; no cache-name mangling is needed. Data in
Application Support/Documents survives ordinary app updates but is removed by
uninstallation. Bundle files are present on every install of that build.

## Resolver and verification boundaries

`OfflineModelAssets` searches the app bundle first, then Application Support and
Documents `OfflineModels`, then known legacy locations. MLX generation receives
the resolved **leaf directory** explicitly. Its SDK's remote model-ID loader is
used only by the explicit prefetch action. This fixes both Documents versus HF
snapshot mismatch and false readiness from an empty snapshot directory.

MLX readiness checks JSON tokenizer/config files, all indexed shards, and the
safetensors header/payload bounds. Parakeet checks all three compiled model
folders and vocabulary; packaged manifests additionally check every staged file
size. Build-time SHA-256 verification protects against same-size corruption.
Runtime file checks do not rehash gigabytes for every availability query and do
not promise semantic tensor compatibility. The signed bundle protects embedded
resources; mutable Documents imports should be byte-verified on the install Mac.
Inference load failures remain visible and never trigger a download fallback.

Granite's explicitly selected bookmark folder remains an operator override;
its local loader reads that directory and errors locally for invalid assets.
It cannot cause a remote model-ID fetch.

## Pairing recommendation and evidence

Use **Parakeet EOU 120M 160ms + LFM2 1.2B 4-bit as the first wholly app-packaged
comparison pair in Yap Lab**, keeping the current Apple defaults until a matched
physical-device comparison supports changing them. This is an engineering
recommendation from footprint and architecture, not a measured TCCC quality win.
Parakeet's CoreML execution and LFM2's small MLX weights make a plausible resource
split. Test sustained microphone capture with generation afterward before
attempting concurrent generation under thermal load.

The current adapter actually loads **LFM2**, not LFM2.5. Earlier repository prose
attached LFM2.5 phone speed claims to LFM2; those figures cannot establish this
artifact's performance. Liquid describes LFM2 as a hybrid convolution/attention
model for edge deployment and recommends narrow task fine-tuning; that is vendor
positioning, not evidence of correct clinical output.
[Liquid's LFM2 model card](https://huggingface.co/LiquidAI/LFM2-1.2B).

FluidInference reports LibriSpeech test-clean WER **8.29%** and **4.78×** real-time
throughput for the 160ms variant on **Apple M2**. Its 320ms model has different
results and requires different weights. These vendor results are not iPhone 17
Pro measurements and do not measure noisy field medical vocabulary.
[Parakeet conversion/model card](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml).

The repository's September 8 matched synthetic **Apple Speech** device result
is WER **20.74%**, five deletions and **6/8** focused extraction checks. This is
an authored synthetic fixture result, not a general clinical accuracy estimate.
See `docs/superpowers/plans/2026-09-08-extraction-reliability.md`. No matched
Parakeet/LFM2/Qwen/Granite result collected by this asset-preparation task justifies
a winner claim. Yap Lab should retain raw text and compare identical audio,
prompts, first-token/total time, thermal state and extraction checks.

Qwen 3 1.7B is the Apache-2.0 comparison/fallback with a larger disk footprint.
Granite text **base** is a base-model research lane; do not equate its output
with an instruction-tuned model. Granite Speech remains a separate ASR candidate,
with larger assets and unmeasured sustained-phone performance here.
[Qwen model card](https://huggingface.co/Qwen/Qwen3-1.7B),
[IBM Granite base model card](https://huggingface.co/ibm-granite/granite-4.0-h-1b-base).

## Distribution terms

Preserve each upstream model card, license and notices in model packages.
Qwen/Granite/Kokoro advertise Apache-2.0; retain the license and applicable attribution.
Liquid uses LFM Open License v1.0, including its commercial-use threshold and
redistribution conditions; it is not simply Apache-2.0. NVIDIA's Open Model
License requires its agreement and a Notice attribution on distribution and
incorporates its Trustworthy AI terms. The staging tool includes these license
copies and the NVIDIA Notice. These conditions need review for the actual
recipient/organization/use; an app build cannot certify organizational compliance.
[Liquid license](https://huggingface.co/LiquidAI/LFM2-1.2B/blob/main/LICENSE),
[NVIDIA agreement](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/),
[NVIDIA incorporated terms](https://www.nvidia.com/en-us/agreements/trustworthy-ai/terms/).

## Kokoro TTS local path

Kokoro is included as the sixth package, with both synthesis models, English
G2P encoder/decoder, vocabulary/lexicon resources and all 54 upstream voice JSON
files. The adapter directly loads CoreML models and injects `TtsModels` into
`initialize(models:)`. It never calls the SDK's `TtsModels.download` initializer.
Because FluidAudio hard-codes auxiliary cache paths, required local auxiliary
files are materialized from the signed package before SDK initialization and
synthesis. Missing resources fail locally and take the existing labeled Device
Speech fallback. Non-American voice selections also take that fallback instead
of silently substituting `af_heart`; the English CoreML lane remains the tested
scope. Asset presence alone does not establish multilingual synthesis quality.
The pitch control applies to Device Speech, not the CoreML renderer.
[Upstream Kokoro card and Apache-2.0 declaration](https://huggingface.co/FluidInference/kokoro-82m-coreml).

Final six-model staging output on this Mac:
`/Users/ama/Documents/ChatGPT/TCCC project/private-model-staging-20260909/OfflineModels-complete`.
Its manifests cover **5,749,589,446 bytes** of model/auxiliary/license content.
Earlier five-model staging outputs are superseded. No clinical data is included.

## Verification from this implementation task

- 14 `OfflineModelAssetsTests` run against the actual Foundation helper on macOS:
  0 failures. Covers empty caches, index-only/missing shards, truncated payloads,
  LFS pointers, unsafe relative paths, manifest truncation, resolver fallback,
  incomplete Parakeet and missing Kokoro resources.
- Five Python staging tests: 0 failures, including same-size corruption and stale
  unlisted files. Required-assets build mode rejects a missing model directory.
- All six downloaded models passed upstream checksums, final manifest SHA-256
  verification and the native app resolver's actual-file inspection.
- `embed_offline_models.sh` executed with simulated Xcode resource paths; both
  source and copied app-resource trees passed verification at 5,749,589,446 bytes.
- Swift parse/type checks passed for the isolated helper/changed source. Full app
  integration, signing, new-container offline inference and physical acoustic
  comparisons are owned by the lead task and are not claimed by these checks.
