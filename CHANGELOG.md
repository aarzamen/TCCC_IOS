# Changelog

Notable changes to TCCC.ai iOS. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The version is
`CFBundleShortVersionString`; the build number is the commit count, stamped at
build time (Settings → System shows both with the git SHA).

## [1.0.0] — unreleased

v1.0 is a declared stopping point, decided 2026-10-27 in
[docs/SCOPE.md](docs/SCOPE.md): what exists today minus anything broken or
half-built, plus the one deliverable this app was always for. The tag is set
once the removals below have landed.

### 1.0.0 delivers

- Five-screen TCCC workflow: Live Capture, Vital Signs Log (DD 1380 §C), TCCC
  Card, MEDEVAC (GPS Line 1) and Handoff.
- Official DD Form 1380 (JUL 2025) export, filled deterministically from
  structured state and flattened: a named tourniquet device fills the TQ box,
  named drugs print on the medication rows, Notes overflow to a second card
  labelled "#2", and nothing is inferred.
- Event-sourced persistence: an append-only encounter log written continuously
  with `NSFileProtectionComplete`, crash recovery by replay, New / End archive,
  Wipe purge.
- Speech: Apple Speech on-device, with deterministic repair of recognition
  errors observed on device; Qwen3-ASR 0.6B is the planned optional second
  backend (not yet in the build).
- Vibeat S5W pulse oximeter over local Bluetooth, labelled unvalidated,
  recorded only after explicit casualty association.
- Supplementary exports (JSON, audio + transcript, vitals CSV, offline QR) and
  approximate 9-line MEDEVAC and ZMIST with validators.
- In-app build stamp: version, build number, git SHA, branch, build date.

### Removed before the tag (per SCOPE; still in the tree on 2026-11-05)

- Yap Lab and the DevTools "Receiver mode" placeholder.
- Alternative backends: Parakeet and Granite Speech (speech); LFM2.5, Qwen 3
  1.7B and Granite text (language model), with their weights.
- The NFC handoff destination and other dead scaffolding.

### Accepted limits

- Not a cleared medical device; not clinically validated or security-audited.
- The 9-line and ZMIST are approximations for the operator to check, not
  validated outputs.
- Pulse-oximeter values are unvalidated; open physical checks are listed in
  `docs/testing/2026-09-18-wireless-vitals-validation.md`.
- Medical-word speech errors (tourniquet, tranexamic acid) still occur; review
  every extracted intervention before handoff.
- Identity fields (name, service number, unit, allergies) are blank unless
  entered on the TCCC Card; there is no roster integration.

### Changed on 2026-11-05 (public-repository pass)

- MIT licence; `THIRD_PARTY.md`; `ARCHITECTURE.md` (draft walkthrough map);
  README rewritten from SCOPE; `CHANGELOG.md`.
- Signing team ID moved to the untracked `Config/Signing.xcconfig`; the
  signing warning keeps only its public half; no home paths in tracked files;
  agent-era notes moved to `docs/history/`.
- Build number from the commit count; `scripts/archive_and_export.sh`
  produces `TCCC-<version>-<sha>.ipa`.
- Extraction: Mobic recognised as meloxicam, ertapenem named, each named drug
  its own DD 1380 row, Notes no longer repeat Antibiotics / Pain mgmt /
  Hypothermia; "is it true rate" and "her pen" repaired from the first live
  recording.
- Handoff shows "review every extracted intervention before export" next to
  the DD 1380 export.

## Earlier milestones

Sprint tags without version numbers, newest first:
`extraction-reliability-2026-09-08`, `speech-coverage-2026-09-08`,
`capture-reliability-2026-09-08`, `sprint-1-granite-speech-foundation`
(2026-05-10). Their records are under `docs/superpowers/` and `docs/history/`.
