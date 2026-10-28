DECIDED 2026-10-27 · stopping-point

# TCCC.ai iOS — v1.0 scope

v1.0 is a declared stopping point, not more features: what exists today minus
anything broken or half-built, plus the one deliverable this app was always
for. That deliverable is a filled-in, official DD Form 1380, produced at the
very end, when all the processing is complete and I ask for it. The 9-line
MEDEVAC and the ZMIST handoff are happy accidents along the way. They can be
approximate and a little messy. The DD 1380 cannot.

## v1.0 keeps

- The five TCCC screens: Live Capture, Vital Signs (DD 1380 §C), TCCC Card,
  MEDEVAC (GPS Line 1) and Handoff.
- Speech recognition: **Apple Speech** (default) and **Qwen3-ASR 0.6B**
  (on-device, offline, optional).
- Language model: Apple Foundation Models, for the optional drafts (narrative,
  ZMIST wording, radio script). No language model writes the DD 1380.
- The **Vibeat S5W pulse oximeter**, labelled as an unvalidated consumer
  sensor. Readings enter the record only after explicit casualty association.
- Continuous encrypted persistence: crash recovery, New / End archive, Wipe.
- Exports: DD 1380 PDF, JSON, audio + transcript, CSV, offline QR.
- The in-app build stamp (Settings → System).

## v1.0 removes or archives

- **Yap Lab**: removed from the launcher. The code is archived on a branch or
  tag, not lost.
- **Blood-pressure monitor and any other sensor family**: not in v1.0. None
  is built; the wireless direction mentions one as future work.
- **Alternative backends**: Parakeet and Granite Speech (speech), LFM2.5,
  Qwen 3 1.7B and Granite text (language model, Granite "hot-seat" review).
  They are removed from Settings, and their weights leave the offline model pack.
- Dead scaffolding: the NFC handoff destination, the DevTools "Receiver mode —
  coming soon" screen, the unused `PlaceholderBody` view.

## Work left before tagging v1.0

1. **Official DD Form 1380.** Done 2026-10-27 on branch
   `claude/dd1380-official-form` (plan:
   `docs/superpowers/plans/2026-10-27-dd1380-official-form.md`). Bundle the official fillable form (a US
   government form, public domain) and fill its fields from the engine's
   structured state: deterministic, the same mapping as today's
   `DD1380Mapper`, no language model. Flatten it, and export it from Handoff
   when the operator asks at end of care. It replaces the current fallback
   layout. Fields that were never captured stay blank; unknown allergies never
   become NKDA.
2. **Qwen3-ASR 0.6B as a speech option.** Not built yet. The Swift audio
   library the app already uses (`mlx-audio-swift`, at its pinned revision)
   includes the model. The 0.7 GB (4-bit) or 1.0 GB (8-bit) weights join the
   offline model pack in place of the removed backends.
3. **Remove** what is listed above, and make the README match this file.

## Accepted limits in v1.0

- Not a cleared medical device; not clinically validated or security-audited.
- The 9-line and ZMIST are approximations for the operator to check, not
  validated outputs.
- Pulse-oximeter values are unvalidated. The open physical checks in
  `docs/testing/2026-09-18-wireless-vitals-validation.md` are either walked
  before the tag or listed here as known limits.
- Medical-word speech errors (tourniquet, tranexamic acid) still occur; review
  every extracted intervention before handoff.
- Identity fields (name, service number, unit, allergies) are blank unless
  entered on the TCCC Card; there is no roster integration.

## Still open

- DevTools: hidden in Release builds, or kept?
- Qwen3-ASR 4-bit or 8-bit: decide after running the TCCC benchmark recordings
  with Apple Speech in the same run.
- DD 1380 edition: done 2026-10-28. The app fills **DD Form 1380, JUL 2025**
  (instructions "Updated 20250721"; same fields as JUN 2014, "Gender" printed
  as "Sex"), from the esd.whs.mil file the owner chose (SHA-256
  `2e5df8d7…f633523`). That file is damaged, not just restricted: it was
  optimized after encryption, so 493 of 1,438 objects decrypt under the wrong
  key and every reader except Adobe's shows blank pages.
  `tools/repair_dd1380_jul2025.py` repairs it; `tools/prepare_dd1380_template.py`
  redraws the pages with `pdftocairo` (PDFKit draws the repaired pages blank)
  and keeps the form's own 305 fields, renamed to the app's flat names. Every
  field was checked against the print on a render; key ones are pinned in the
  tool. References, local-only:
  `reference/rubric/TCCC rubrics and guidelines/2025 updates/`.
- Body diagram: the JTS Module 23 skills checklist (TCCC-CPP-12-02, 15 MAY
  2025) grades "marked injury sites with an X" as a **critical** task. v1.0
  leaves the diagram blank and lists injuries in Notes; marking confident
  sites is the next DD 1380 change.
- Tourniquet type: done. The JUL 2025 instructions say "write type of
  tourniquet used"; a device the medic names ("CAT tourniquet") fills the limb
  box and the Treatments Type line. None is ever guessed.
- Continuation: done. Per the JTS card guide (TCCC-CMC-SC-64, 15 MAY 2025),
  notes that overflow go onto a second official DD 1380 labelled "#2" (then
  "#3"…), repeating the header, name and unit.
