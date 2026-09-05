# Development while away from the Mac

Work can proceed through a branch and draft pull request while the operator is
unavailable. A draft is a saved review point, not permission to merge or deploy.
Keep a short PR description with the problem, change, evidence, and remaining
device checks so resumption does not require reading an entire conversation.

## Automated gate

`.github/workflows/ci.yml` runs on pull requests, pushes to `main`, and manual
workflow dispatch. It uses the existing macOS 15 / Xcode 26.2 baseline and:

1. Runs all TCCCKit package tests.
2. Generates the Xcode project from `project.yml` and resolves dependencies.
3. Creates a fresh iPhone 17 Pro simulator on iOS 26.2.
4. Builds and runs the entire `TCCC_IOSTests` target, with serial test execution
   and bounded test timeouts. No test classes are excluded.
5. Checks the Xcode result bundle for a nonzero passing test count, preventing
   an accidentally empty scheme or test filter from passing the gate.

The workflow has read-only repository permissions. It does not sign a device
build, publish to TestFlight, change app defaults, or merge a PR. Newer pushes
cancel obsolete runs on the same PR. Shell pipelines preserve command failures
even when output is also copied to a log.

## Evidence and failures

Open the PR's **Checks** tab, then the **CI** run. The job summary separates
package tests, simulator tests, and the test-count check. Download the
`tccc-ci-<run-id>-<attempt>` artifact for raw logs, build identity, simulator
inventory, and `app-tests.xcresult` when Xcode produced it. Open that bundle in
Xcode for individual test failures. Diagnostics are retained for 14 days;
capture durable conclusions and the run URL in the PR before they expire.

An Xcode/runtime disappearance should be fixed explicitly in the workflow;
do not silently switch compiler versions. A test failure should be reproduced
and investigated, not hidden with an exclusion or `continue-on-error`.

Two tests currently require explicit local model setup. Leave
`TCCC_RUN_REAL_MODEL`, `SIMCTL_CHILD_TCCC_RUN_REAL_MODEL`, and
`GRANITE_SPEECH_MODEL_DIR` unset in ordinary CI. Existing tests report their
own skips. A skip is not validation of that model. Source dependencies download
during the build; runtime speech/LLM weight downloads are not enabled by CI.

## Work that still needs a physical iPhone

Passing CI establishes software behavior covered by these tests and simulator
compatibility. It does not establish microphone routing, speech quality,
interruption handling on hardware, cold-start offline model availability,
thermal/battery performance, or clinical correctness. Keep those as explicit
pending checks for audio, model, lifecycle, or clinical extraction changes.

Use synthetic, non-identifying cases in this public repository and hosted CI.
Physical-device recordings and real encounter data stay outside that workflow.
Before merging substantial branch work after a long field interval, reconcile
any newer, unpushed Mac changes with the branch's recorded base commit.
