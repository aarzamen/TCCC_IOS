<!-- apple-developer-kit:generated v1 2026-09-22 — regenerate: ~/apple-developer-kit/scripts/apple-dev-place-warnings.py -->
# ⚠️ APPLE DEVELOPER SIGNING — READ BEFORE TOUCHING BUILD SETTINGS

**Project:** `TCCC_IOS` · **Root:** `/Users/ama/TCCC_IOS` · **Remote:** https://github.com/aarzamen/TCCC_IOS.git · **Generated:** 2026-09-22

This file is a sign for AI agents and humans. It was placed here because this project carries Apple
code-signing material or configuration. It does **not** change anything in the project. Do not delete
it; do not "fix" the project's signing to match a guess.

## The facts (verified 2026-09-22)

- **Team ID: `XM6E4PUXTU`** — team "Aaron Arzamendi", **paid** Apple Developer Program (Individual), renews **2027-04-05**.
- **`434HG698U6` is NOT a Team ID.** It is the certificate user ID inside
  `Apple Development: Aaron Arzamendi (434HG698U6)`. Using it as `DEVELOPMENT_TEAM` produces
  `No Account for Team "434HG698U6"`.
- "SideStore, no Apple Developer Program" in old notes is **false**. The App Store Connect
  "Membership Expired" banner is **stale**; developer.apple.com › Membership details is authoritative.
- Two Apple Development identities share one name → sign by SHA-1
  (`99BD3B7D50BBD87441211E39DFF5DC5BC7B543D3`, valid to 2027-09-19).
- No Apple Distribution / Developer ID Application certificate exists → no TestFlight, App Store
  upload, or notarization until the Account Holder creates one.

## Rules for AI agents

1. Team ID is `XM6E4PUXTU`. Never write `434HG698U6` as a team anywhere.
2. Do not touch the Apple Developer account: no creating/revoking certificates, no registering App
   IDs, devices, keys, containers, or capabilities, no `-allowProvisioningUpdates` /
   `-allowProvisioningDeviceRegistration`, no SideStore/AltStore, without the user's explicit OK
   in the same session.
3. Build with the profiles that exist. If one is missing or stale, stop and ask the user for one
   automatic-signing build in the Xcode GUI.
4. Secrets (`.p12`, `.p8`, `.mobileprovision`, `.cer`, keychains) never go inside this repository.
   In public repositories the Team ID comes from env/config, never a literal.
5. XcodeGen projects: `project.yml` is the source of truth; the generated `.xcodeproj` is disposable.
6. Read `~/apple-developer-kit/APPLE_DEVELOPER_ACCOUNT.md` and run
   `~/apple-developer-kit/scripts/apple-dev-status.sh` before giving signing advice.

## This project's signing footprint (scan of 2026-09-22)

- `.github/workflows/ci.yml`: CODE_SIGNING_ALLOWED=NO, CODE_SIGNING_ALLOWED=NO \
- `AGENTS.md`: CODE_SIGNING_ALLOWED=NO \
- `CLAUDE.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation, CODE_SIGNING_ALLOWED=NO -skipMacroValidation
- `README.md`: CODE_SIGNING_ALLOWED=NO \
- `TCCC_IOS.xcodeproj/project.pbxproj`: DevelopmentTeam=XM6E4PUXTU, DevelopmentTeam=XM6E4PUXTU, PRODUCT_BUNDLE_IDENTIFIER=com.aarzamen.TCCCaiTests, CODE_SIGN_STYLE=Automatic … (+8)
- `docs/design/swiftui-reference-port.md`: CODE_SIGNING_ALLOWED=NO
- `docs/devtools/orchestrator-self-review.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation`
- `docs/devtools/self-review-agent-a.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation`
- `docs/devtools/self-review-agent-c.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation`.
- `docs/devtools/self-review-agent-d.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation` passed after the Xcode project had been regenerated to include DevTools sources.
- `docs/devtools/sim-coverage-gaps.md`: CODE_SIGNING_ALLOWED=NO`.
- `docs/granite/INSTRUCTIONS_FOR_AGENTS.md`: CODE_SIGNING_ALLOWED=NO \, CODE_SIGNING_ALLOWED=NO \
- `docs/granite/SPRINT_BOARD.yaml`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation, CODE_SIGNING_ALLOWED=NO -skipMacroValidation, CODE_SIGNING_ALLOWED=NO -skipMacroValidation, CODE_SIGNING_ALLOWED=NO -skipMacroValidation … (+7)
- `docs/granite/SPRINT_CONTEXT.md`: CODE_SIGNING_ALLOWED=NO \
- `docs/specs/v3_sprint_1_granite_foundation.md`: CODE_SIGNING_ALLOWED=NO \
- `docs/superpowers/2026-06-24-next-cycle-event-sourcing-kickoff.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:...`
- `docs/superpowers/plans/2026-05-05-llm-backends.md`: CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20, CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10, CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
- `docs/superpowers/plans/2026-05-05-long-form-recording.md`: CODE_SIGNING_ALLOWED=NO \, CODE_SIGNING_ALLOWED=NO \, CODE_SIGNING_ALLOWED=NO \, CODE_SIGNING_ALLOWED=NO \ … (+8)
- `docs/superpowers/plans/2026-05-05-review-hardening.md`: CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5, CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5, CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5, CODE_SIGNING_ALLOWED=NO … (+1)
- `docs/superpowers/plans/2026-05-07-devtools-kokoro-splash.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation, CODE_SIGNING_ALLOWED=NO -skipMacroValidation
- `docs/superpowers/plans/2026-05-07-granite-hot-seat.md`: CODE_SIGNING_ALLOWED=NO \, CODE_SIGNING_ALLOWED=NO \, CODE_SIGNING_ALLOWED=NO \
- `docs/superpowers/plans/2026-05-07-granite-sprint-2.md`: CODE_SIGNING_ALLOWED=NO \
- `docs/superpowers/plans/2026-06-24-reconciliation-apply-path.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/, CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/FieldRouterBoundaryGateTests`, CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/FieldRouterBoundaryGateTests`, CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/DeterministicFactProjectorTests` … (+11)
- `docs/superpowers/plans/2026-06-25-engine-incremental-projection.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests`
- `docs/superpowers/plans/2026-06-25-event-sourcing-archive.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation \
- `docs/superpowers/plans/2026-06-25-event-sourcing-core.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation \
- `docs/superpowers/plans/2026-06-28-asr-provisional-replace.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation`., CODE_SIGNING_ALLOWED=NO -skipMacroValidation`, CODE_SIGNING_ALLOWED=NO -skipMacroValidation`
- `docs/superpowers/plans/2026-07-02-phase01-buildstamp-benchmark-plan.md`: CODE_SIGNING_ALLOWED=NO -skipMacroValidation \, CODE_SIGNING_ALLOWED=NO -skipMacroValidation | tail -2, CODE_SIGNING_ALLOWED=NO -skipMacroValidation | tail -2 && \, CODE_SIGNING_ALLOWED=NO -skipMacroValidation 2>&1 | tail -3 … (+1)
- `project.yml`: bundleIdPrefix=com.aarzamen, DEVELOPMENT_TEAM=XM6E4PUXTU, CODE_SIGN_STYLE=Automatic, PRODUCT_BUNDLE_IDENTIFIER=com.aarzamen.TCCCai … (+1)
- Apple project marker: `Packages/TCCCAudio/Package.swift`
- Apple project marker: `Packages/TCCCDesignSystem/Package.swift`
- Apple project marker: `Packages/TCCCKit/Package.swift`
- Apple project marker: `Packages/TCCCLLM/Package.swift`
- Apple project marker: `TCCC_IOS.xcodeproj`
- Apple project marker: `project.yml`

## Alerts for this project

- ℹ️ Team ID literal `XM6E4PUXTU` is committed (TCCC_IOS.xcodeproj/project.pbxproj:979, TCCC_IOS.xcodeproj/project.pbxproj:983, TCCC_IOS.xcodeproj/project.pbxproj:1355). Not a secret, but if this repository is public prefer env/config (see appifier's `~/.appifier/config` pattern).
- ⚠️ Mentions altstore (RESEARCH_LLAMA32B.md) — sideloading/free-team paths are obsolete; the paid team signs directly.

## Bundle identifiers seen

- `com.aarzamen.TCCCaiTests`
- `com.aarzamen.TCCCai`
- `com.aarzamen`

---
Canonical truth: `~/apple-developer-kit/APPLE_DEVELOPER_ACCOUNT.md` · Skill: `apple-developer` ·
Regenerate this file: `~/apple-developer-kit/scripts/apple-dev-scan.py <root> --json /tmp/scan.json && ~/apple-developer-kit/scripts/apple-dev-place-warnings.py /tmp/scan.json --apply`
