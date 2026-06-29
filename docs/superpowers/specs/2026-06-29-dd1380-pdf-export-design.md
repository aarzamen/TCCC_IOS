# Design — Deterministic DD Form 1380 PDF Export — 2026-06-29

## Context

DD Form 1380 is the rubric's **primary deliverable** (2026 §19) and the #1
backlog item — the Handoff "Primary · DD 1380" card is still `Pending PDFKit`.
This builds the deterministic fill pipeline:

```
PatientState + AppState metadata + Section C readings + operator profile
  → DD1380MapperInput → DD1380Mapper → DD1380CardData
  → DD1380PDFRenderer → DD1380PDFExportService (ProtectedWrite)
  → Handoff share sheet
```

**The LLM never fills, invents, or mutates DD1380 fields.** Source data is
structured `PatientState` + app metadata only — never narrative/ZMIST prose.
Unknown fields stay blank; nothing is hallucinated. Output is deterministic:
same input → identical `DD1380CardData`.

## Grounding (what actually exists — verified)

- **Identity is mock app-state**: `AppState.casualtyName` (`"DOE, J."`),
  `casualtyServiceNumberMasked` (`"••• 4471"`), `casualtyUnit`,
  `casualtyAllergies`. **No** sex/gender, service branch, battle-roster, or
  unmasked last-4 exists anywhere. Operator identity is `operatorCallsign`
  only (no real name / last-4).
- **`PatientState`**: `mechanismOfInjury: String?`, `classification:
  Classification?` (urgent/urgentSurgical/priority/routine/expectant),
  `march: MARCHState` (all `String?`/`Bool` — no structured TQ list),
  `vitals: Vitals` (hr/bp/spo2/rr/gcs/temp/crt — **no pain**),
  `interventions: [Intervention{kind: InterventionKind, description, timestamp}]`
  (17 structured kinds), `injuries: [String]`, `paws` (pain/antibiotics/
  wounds/splinting strings).
- **`AppState.vitalsLog: [SectionCReading{id, timestamp, vitals, avpu}]`** is a
  4-deep rolling buffer that is **ephemeral** (not persisted; lost on relaunch).
- **No DD1380 template is bundled** in the app target (one exists only under
  `reference/`). → vector-rendered **fallback** form, clearly labeled.
- `ProtectedWrite.data(_:to:)`, `ExportCard(icon,title,detail,isReady,action?)`,
  `ShareSheet(items:onDismiss:)`, `EncounterStore` actor (active encounter dir),
  `AppState.documentsURL` — all confirmed.

## Part A/B — TCCCKit model + mapper (`TCCCReports`)

`DD1380CardData` (Codable/Equatable/Sendable) models the **form fields**, §A–H,
keyed to `dd1380_field_inventory.json`. Mechanism flags use the rubric's 11
allowed values (Artillery/Blunt/Burn/Fall/Grenade/GSW/IED/Landmine/MVC/RPG/
Other), **not** the task's suggested 7. Plus `DD1380MapperInput` (pure DTO) and
`DD1380Mapper.map(_:) -> DD1380CardData`.

Mapping rules (deterministic; structured fields only):
- **EVAC**: urgent/urgentSurgical → `.urgent`; priority → `.priority`;
  routine → `.routine`; expectant/nil → blank.
- **Identity**: name/unit/allergies verbatim from app state; `last4` = trailing
  digits of the masked service number; `battleRoster` = first-initial +
  last-initial (from "Last, First") + last4, per the field's own definition
  (composing existing data, not inventing) — blank if name+last4 absent;
  sex/service blank (no source).
- **Date/Time of injury**: from `encounterStart`, Zulu — `DATE` `DD-MMM-YY`,
  `TIME` `HHMMZ` (en_US_POSIX, GMT, fixed → deterministic).
- **Mechanism**: case-insensitive keyword match of `mechanismOfInjury` →
  flags; unrecognized text → `otherText` + Notes.
- **Injury**: no confident body-map coordinates → `injuryMarks` stays empty;
  `hemorrhageLocation` + `injuries[]` go to **Notes** (per task).
- **Tourniquets**: from `interventions` of kind `.tourniquet` — time =
  `intervention.timestamp` (HHMM); limb mapped from `hemorrhageLocation` when
  recognizable (else raw text); **type blank** (never inferred).
- **Section C**: up to 4 readings, passed in pre-converted; AVPU text →
  A/V/P/U; pain blank (no source).
- **Treatments §E**: from `InterventionKind` (tourniquet→TQ extremity,
  pressureDressing→pressure, dressing/woundCare→hemostatic/other,
  npa→NPA, surgicalAirway→CRIC, chestSeal→Chest-Seal,
  needleDecompression→Needle-D) + MARCH fallback. Fluids/blood unsupported by
  the domain → empty.
- **Meds §F**: from `interventions` of kind `.medication/.antibiotic/
  .painManagement` — name = `description` **verbatim** (no prose parsing),
  time from timestamp, dose/route blank. Hypothermia/splint → OTHER flags.
- **Notes §G**: deterministic assembly of unmapped structured facts (injury
  locations, mechanism-other, breath sounds/skin/pulse, hypothermia/splint
  type). **No LLM prose. No GPS/MGRS** (that's 9-Line Line 1).
- **First responder §H**: `operatorCallsign` → name; last-4 blank.

`DD1380Readiness.evaluate(card:) -> DD1380ReadinessResult` (Part F): reports
patient-identity / date-time / clinical-content / section-C / first-responder
presence + `criticalMissing` required fields. Informs UI text; **never blocks**
generation (a partial DD1380 beats none).

## Part C — Section C persistence

`AppState.SectionCReading` becomes `Codable`; `EncounterStore` gains
`saveSectionC(_:)` / `loadSectionC()` writing a protected `sectionC.json` in the
active encounter dir. `AppState` persists the buffer on each append and restores
it in `load()` **before** the post-restore snapshot — so the exporter no longer
depends on ephemeral UI state and the §C grid survives crash recovery.
App-layer only (vitalsLog is not part of `PatientState`; the event-sourcing
invariant is untouched). A round-trip test gates it.

## Part D — PDF renderer + export service (app target)

`enum DD1380PDFRenderer { static func render(_:) throws -> Data }` —
`UIGraphicsPDFRenderer`, **two pages** (front §A–C, back §D–H), US-Letter,
coordinates in one centralized field-map struct, long notes wrapped/clipped
deterministically. Header clearly marks it a **FALLBACK layout, not an official
DD Form 1380 facsimile**.

`actor DD1380PDFExportService { func export(card:casualtyId:documentsURL:)
async throws -> URL }` — renders → `ProtectedWrite.data` →
`DD1380_<casualtyId>_<yyyyMMdd-HHmmss>.pdf` (id sanitized). Protected at rest.
No auto-share/transmit.

## Part E — Handoff wiring

`AppState.makeDD1380Card() -> DD1380CardData?` assembles the input from app
state + maps (nil when no patient) — the testable seam. `HandoffScreen` replaces
the placeholder card: title `DD-1380 PDF`, detail `Ready · 2 pages · CUI when
filled` (patient) / `No casualty state` (none), `isReady: patient != nil`,
action `shareDD1380PDF()` → render → protected write → existing ShareSheet.
Failure → visible system message. Never crashes on blank fields.

## Tests (Part G)

- **TCCCKit `DD1380MapperTests`**: empty state blank-not-crash; GSW+TQ maps
  mechanism/location/TQ; classification→EVAC; vitals→§C; meds only if in
  structured state; unknown med details blank; Notes carry unmapped structured
  facts (no prose); determinism (identical output).
- **App `DD1380PDFRendererTests`**: non-empty Data; 2 pages (CGPDFDocument);
  missing optionals don't crash; long notes don't crash.
- **App `DD1380PDFExportServiceTests`**: writes a `.pdf`; exists; non-empty;
  protected.
- **App Section C / wiring**: §C survives `EncounterStore` round-trip;
  `makeDD1380Card` nil without patient, non-nil with.

## Commits

1. DD1380 model + mapper + readiness + `DD1380MapperTests` (TCCCKit).
2. Section C `Codable` + `EncounterStore` persistence + conversion + test.
3. PDF renderer + export service + app tests.
4. Handoff wiring (`makeDD1380Card`, `shareDD1380PDF`, card) + wiring tests.
5. Verification + docs (README/CLAUDE.md backlog flip).

## Out of scope (do not broaden)

GPS, ATAK/MEDHUB, radio transmit, LLM form-fill, UI redesign, new clinical
decision logic, cloud sync, official-template overlay (fallback only).
