# Official DD Form 1380 Fill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Handoff "DD-1380 PDF" export produces the official DD Form 1380 (JUN 2014), filled from the engine's structured state and flattened, instead of the vector fallback layout.

**Architecture:** A one-time Python tool turns the official fillable PDF into an app template: it strips the XFA layer, verifies every field's position on the page, and renames fields to honest flat names, because the original names and tooltips are wrong in places. TCCCKit gets a pure mapping from `DD1380CardData` to those field names, with overflow rules, all unit-tested with `swift test`. The app target gets a thin PDFKit filler that writes the values, adds a continuation page for long notes, and flattens. The export service uses it and keeps the old renderer only as an error fallback.

**Tech Stack:** Swift 6 / PDFKit (iOS 26), TCCCKit SwiftPM, Python 3.12 + pypdf + pymupdf via `uv` (tool only, never shipped).

**Spec:** `docs/SCOPE.md` ("Work left before tagging v1.0", item 1) and `docs/superpowers/specs/2026-06-29-dd1380-pdf-export-design.md` (mapper rules, protection, no LLM).

## Global Constraints

- The language model never writes the DD 1380. Values come only from `DD1380CardData`, produced by `DD1380Mapper`.
- Unknown fields stay blank. Blank allergies are never written as NKDA. No device type, dose or route is invented.
- Clinical data is never silently dropped. Anything that does not fit its row or box goes to Notes, and Notes that do not fit go to a continuation page.
- Output is written with `ProtectedWrite` (`NSFileProtectionComplete`) and shared only on explicit operator action. No network.
- No logic in the app target: the field mapping and the overflow rules live in TCCCKit.
- `project.yml` is the source of truth. Regenerate with `xcodegen generate` and never hand-edit the `.xcodeproj`.
- Builds use `-skipMacroValidation`. No `-allowProvisioningUpdates`.

## Review Focus

1. **Field names that lie.** `PressureDressing` is the Truncal-TQ box, `HemoDressing[1]` is Pressure, `HemoDressing[2]` is Other, and `TypeSGA[0/1/2]` are the Airway, TQ and Dressing type lines. The tool asserts each field's page and rectangle before renaming, and fails loudly on any mismatch (Task 1).
2. **More entries than rows.** Analgesic has 3 rows, Antibiotic 2, Other medication 2, Fluid 2, Blood product 2, vitals 4 columns, and 1 tourniquet slot per limb. Extras go to Notes as plain lines (Task 2 tests).
3. **Long notes.** The Notes box holds about 11 lines. Overflow is cut at a line boundary and appears on a continuation page titled with the casualty's BR# (Task 2 split tests, Task 3 page-count test).
4. **Blood pressure not in "S/D" form.** "120/80" splits into SBP and DBP. Anything else goes whole into SBP, and DBP stays blank (Task 2 test).
5. **A blank card.** Every text value is empty and nothing is checked, so the exported form is the unfilled official form plus nothing invented (Task 2 test). The template failing to load falls back to the labelled vector renderer, never to no export (Task 4 test).

---

### Task 1: App template from the official form

**Files:**
- Create: `tools/prepare_dd1380_template.py`
- Create (generated, committed): `TCCC_IOS/Resources/DD1380/DD1380_JUN2014_template.pdf`, `TCCC_IOS/Resources/DD1380/DD1380_JUN2014_fields.json`

**Interfaces:**
- Produces: a PDF with flat, top-level fields named exactly as in the table below. Body-region boxes are kept as `body_<OriginalName>`. All choice fields become text fields. There is no XFA, no JavaScript, and no field actions. The JSON is a sorted array of `{"name", "type": "text"|"checkbox", "page": 0|1, "rect": [x0,y0,x1,y1]}`.

Field map (original terminal name with index → new name; page; rounded rect x0,y0 from the 2026-10-27 inspection):

| Page 0 original | New |
|---|---|
| `BRnumber[0]` | `br_number` |
| `Evac.A-Urgent / B-Priority / C-Routine` | `evac_urgent / evac_priority / evac_routine` |
| `Name`, `Last4SSN`, `Date`, `Time`, `Service`, `Unit`, `Allergies` | `name`, `last4`, `date`, `time`, `service`, `unit`, `allergies` |
| `GenderM`, `GenderF`, `Gender` (1 pt wide) | `sex_m`, `sex_f`, `gender_label_unused` |
| `MOIArtillery … MOIRPG`, `MOIOther`, `MOIOtherSpecify` | `moi_artillery`, `moi_blunt`, `moi_burn`, `moi_fall`, `moi_grenade`, `moi_gsw`, `moi_ied`, `moi_landmine`, `moi_mvc`, `moi_rpg`, `moi_other`, `moi_other_text` (names match position; tooltips do not) |
| `TQRUEType/Time`, `TQRLE…`, `TQLUE…`, `TQLLE…` | `tq_r_arm_type/time`, `tq_r_leg_…`, `tq_l_arm_…`, `tq_l_leg_…` |
| `SS{n}.SignTime/Pulse/SBP/DBP/RespRate/Ox/AVPU/Pain{n}` | `vitals{n}_time/pulse/sbp/dbp/rr/spo2/avpu/pain`, n = 1…4 |

| Page 1 original | New |
|---|---|
| `BRnumber[1]`, `EVAC.A/B/C` | `br_number_back`, `evac_urgent_back / evac_priority_back / evac_routine_back` |
| `ExtremityTQ`, `JuncTQ`, `PressureDressing` (at "Truncal"), `TypeSGA[1]` | `tq_extremity`, `tq_junctional`, `tq_truncal`, `tq_type_text` |
| `HemoDressing[0]`, `HemoDressing[1]`, `HemoDressing[2]`, `TypeSGA[2]` | `dressing_hemostatic`, `dressing_pressure`, `dressing_other`, `dressing_type_text` |
| `Intact`, `NPA`, `Cric`, `ETtube`, `SGA`, `TypeSGA[0]` | `airway_intact`, `airway_npa`, `airway_cric`, `airway_et_tube`, `airway_sga`, `airway_type_text` |
| `O2`, `NeedleD`, `ChestTube`, `ChestSeal`, `TypeChestSeal` | `breathing_o2`, `breathing_needle_d`, `breathing_chest_tube`, `breathing_chest_seal`, `breathing_type_text` |
| `#area[0].FluidName1/2`, `FluidVolume1/2[0]`, `FluidRoute1/2`, `FluidTime1`, `FluiTime2` | `fluid{1,2}_name/volume/route/time` |
| `#area[1].FluidName1/2[1]`, `FluidVolume1/2[1]`, `BPRoute1/2`, `BPTime1/2` | `blood{1,2}_name/volume/route/time` |
| `AnagelsicName/Dose/Route{n}`, `AnalgesicTime{n}` | `analgesic{n}_name/dose/route/time`, n = 1…3 |
| `AntibioticName/Dose/Route/Time{n}` | `antibiotic{n}_…`, n = 1…2 |
| `OtherMedName/Dose/Route{n}`, `OtheMedTime{n}` | `othermed{n}_…`, n = 1…2 |
| `PillPack`, `EyeShield`, `EyeShieldR`, `EyeShieldL`, `Splint`, `HypoTherm`, `HypoThermiaPrevType` | `other_pill_pack`, `other_eye_shield`, `other_eye_shield_r`, `other_eye_shield_l`, `other_splint`, `other_hypothermia`, `other_hypothermia_type` |
| `Notes`, `FirstRespName`, `FirstRespLast4SSN` | `notes`, `responder_name`, `responder_last4` |

- [ ] **Step 1:** Write the tool. Arguments: `--source <official pdf> --out-dir <dir>`. The map is keyed by `(page, original terminal name)`, since every widget carries its own `/T`. Pin the source by SHA-256, and pin the position of the nine fields whose names or tooltips lie, with a 2 pt tolerance. Abort with a non-zero exit on a pin mismatch, a missing mapped name, an unmapped non-checkbox widget, or a name collision. Set Notes to 7 pt ArialMT and multiline, and keep the form's own sizes elsewhere. (As built: the SHA pin plus nine position pins replaced per-field rectangles; the visual check in Step 3 covers the rest.)
- [ ] **Step 2:** Run it: `uv run --python 3.12 --with pypdf --with pymupdf python -I tools/prepare_dd1380_template.py --source "reference/rubric/TCCC rubrics and guidelines/tccc-card-form-1380-en.pdf" --out-dir TCCC_IOS/Resources/DD1380`. Expected: `wrote 2 pages, N fields (0 XFA)`.
- [ ] **Step 3:** Render the output with each new field name drawn on its box (pymupdf, scratch only) and read the images. Expected: every name sits on its printed label, including the Truncal / Pressure / Other boxes and the three Type lines.
- [ ] **Step 4:** Commit the tool, the template and the JSON.

### Task 2: Pure field values in TCCCKit

**Files:**
- Create: `Packages/TCCCKit/Sources/TCCCReports/DD1380OfficialForm.swift`
- Test: `Packages/TCCCKit/Tests/TCCCReportsTests/DD1380OfficialFormTests.swift`

**Interfaces:**
- Consumes: `DD1380CardData` (unchanged) and Task 1's JSON (tests only, via a `#filePath`-relative path).
- Produces:
  - `public struct DD1380FormValues: Sendable, Equatable { public var text: [String: String]; public var checked: Set<String>; public var continuationNotes: String? }`
  - `public enum DD1380OfficialForm { public static let edition = "DD Form 1380, JUN 2014"; public static let templateResource = "DD1380_JUN2014_template"; public static func values(for card: DD1380CardData) -> DD1380FormValues; static func splitNotes(_ notes: String, charsPerLine: Int, maxLines: Int) -> (onForm: String, overflow: String?) }`
  - Constants `notesCharsPerLine = 95`, `notesMaxLines = 11` (confirmed visually in Task 3).

- [ ] **Step 1: Write the failing tests**
  - `testEveryProducedFieldExistsInTemplate`: for a fully populated card, every key in `text` and `checked` is a name in the JSON with the matching type.
  - `testBlankCardWritesNothing`: `values(for: DD1380CardData())` has every `text` value empty or absent, `checked` empty, and `continuationNotes == nil`.
  - `testEvacChecksFrontAndBack`: `.urgent` gives `["evac_urgent", "evac_urgent_back"]` and nothing else from the evac fields.
  - `testBRNumberOnBothPages`: `text["br_number"] == text["br_number_back"] == "JD4471"`.
  - `testBloodPressureSplits`: "120/80" gives `vitals1_sbp == "120"` and `vitals1_dbp == "80"`; "palpable" gives `vitals2_sbp == "palpable"` and `vitals2_dbp` empty.
  - `testVitalsColumnsAndPain`: four readings fill `vitals1…4_*`; pain "7" gives `vitals1_pain == "7"`; AVPU "A" is written as "A".
  - `testTourniquetCorners`: R Leg with time "2213" gives `tq_r_leg_time == "2213"` and `tq_r_leg_type` empty (never inferred). A second R Leg entry and a nil-limb entry with locationText "junctional groin" both appear in `text["notes"]` as lines starting "TQ:".
  - `testMedicationOverflowGoesToNotes`: 4 analgesics fill `analgesic1…3_*`, and the 4th appears in notes as "Analgesic: <name> <time>". The same applies to antibiotics beyond 2, other medications beyond 2, fluids beyond 2 and blood products beyond 2.
  - `testTreatmentBoxes`: `tqTruncal` checks `tq_truncal`, `dressingPressure` checks `dressing_pressure`, and `airwayTypeText` "i-gel" goes to `airway_type_text`. The same holds for every flag in `DD1380TreatmentFlags` and `DD1380OtherTreatmentFlags` (one table-driven test).
  - `testSexAndMechanism`: `.female` checks `sex_f` only; `mechanisms.other` with otherText "blast" checks `moi_other` and writes `moi_other_text == "blast"`.
  - `testNotesSplitAtLineBoundary`: 30 lines of 20 characters give `onForm` with exactly 11 lines and `overflow` with the remaining 19; a single 2,000-character line gives `onForm` cut at a word boundary ≤ 95×11 characters, ending in "… (continued)".
  - `testLongNotesProduceContinuation`: a card whose notes exceed capacity gives `text["notes"]` ending "(continued on next page)" and a `continuationNotes` holding the rest.
- [ ] **Step 2:** Run `cd Packages/TCCCKit && swift test --filter DD1380OfficialFormTests`. Expected: FAIL (`DD1380OfficialForm` undefined).
- [ ] **Step 3:** Implement `DD1380OfficialForm.values(for:)` and `splitNotes`. Notes order: the card's own notes first, then overflow lines in a fixed order (TQ, Analgesic, Antibiotic, Medication, Fluid, Blood), each as one line.
- [ ] **Step 4:** Run the filter again, then the whole `swift test`. Expected: all pass (926 + new).
- [ ] **Step 5:** Commit.

### Task 3: PDFKit filler in the app

**Files:**
- Create: `TCCC_IOS/App/DD1380OfficialFormFiller.swift`
- Test: `TCCC_IOSTests/DD1380OfficialFormFillerTests.swift`

**Interfaces:**
- Consumes: `DD1380OfficialForm.values(for:)`, `DD1380OfficialForm.templateResource`, the bundled template.
- Produces: `enum DD1380OfficialFormFiller { static func render(_ card: DD1380CardData, bundle: Bundle = .main) throws -> Data }` and `enum DD1380FillError: Error { case templateMissing, templateUnreadable, emptyOutput }`.

- [ ] **Step 1: Write the failing tests**
  - `testTemplateFieldsMatchManifest`: the set of widget `fieldName`s in the bundled template equals the names in the bundled JSON.
  - `testFilledFormIsFlattenedOfficialForm`: rendering the `DD1380PDFRendererTests` sample card gives 2 pages, no `.widget` annotations on any page, and page 0 text containing "DD Form 1380, JUN 2014", "DOE, J.", "4471", "120" and "80". Page 1 text contains "Ketamine".
  - `testLongNotesAddContinuationPage`: notes of 40 lines give 3 pages; page 2 text contains the last note line and the BR#.
  - `testWritesSampleForVisualCheck`: writes the sample card's PDF to `FileManager.default.temporaryDirectory/DD1380_sample.pdf` and prints the path (no assertion beyond existence).
- [ ] **Step 2:** Run `xcodebuild test … -only-testing:TCCC_IOSTests/DD1380OfficialFormFillerTests`. Expected: FAIL (type undefined).
- [ ] **Step 3:** Implement. Load the template with `PDFDocument(url:)`. For each page's widget annotations, look up `fieldName`: set `widgetStringValue` for text, and `buttonWidgetState = .onState` for checked boxes. If `continuationNotes` is present, render one US-Letter page with `UIGraphicsPDFRenderer` (title "DD Form 1380 — Notes (continued)", the BR#, name and date, then the overflow text at 10 pt) and insert it as page 2. Return `dataRepresentation(options: [.burnInAnnotationsOption: true])`; throw `.emptyOutput` on nil.
- [ ] **Step 4:** Run the tests. Expected: PASS. Convert the sample PDF to PNG (pymupdf, scratch) and read it. Expected: values sit inside their boxes, the 7 pt Notes text fits 11 lines, and checked boxes show an X or check. Adjust `notesCharsPerLine` / `notesMaxLines` in Task 2 if the visual check disagrees.
- [ ] **Step 5:** Commit.

### Task 4: Wire into export and Handoff

**Files:**
- Modify: `TCCC_IOS/App/DD1380PDFExportService.swift` (use the official filler; fall back to `DD1380PDFRenderer` only on `DD1380FillError`, and report which one was used)
- Modify: `TCCC_IOS/Screens/HandoffScreen.swift` (`dd1380Detail` and the system log line say "official form" or "fallback layout" truthfully)
- Modify: `TCCC_IOS/App/DD1380PDFRenderer.swift` (doc comment: now the error fallback only)
- Modify: `TCCC_IOS.xcodeproj` (regenerated by `xcodegen generate`; new resources and sources)
- Test: `TCCC_IOSTests/DD1380PDFExportServiceTests.swift`

**Interfaces:**
- Produces: `DD1380PDFExportService.export(card:casualtyId:documentsURL:) async throws -> DD1380ExportResult`, with `struct DD1380ExportResult { let url: URL; let usedOfficialForm: Bool }`. Update the Handoff call site.

- [ ] **Step 1: Write the failing tests**
  - `testExportUsesOfficialForm`: `result.usedOfficialForm == true`, and the file's page 0 text contains "DD Form 1380, JUN 2014".
  - `testExportFallsBackWhenTemplateMissing`: exporting with an injected empty bundle gives `usedOfficialForm == false` and a 2-page PDF, not an error.
  - Existing export tests (protection, file naming) still pass after adapting to `DD1380ExportResult`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement the service change, with an `init(bundle: Bundle = .main)` for injection. Update the Handoff wording.
- [ ] **Step 4:** Run `xcodegen generate`, the full simulator test suite, `swift test`, and a simulator build. Expected: all pass, apart from the 3 known skips (complete-protection attribute on the simulator, two optional Granite assets).
- [ ] **Step 5:** Commit. Update `docs/SCOPE.md` (item 1 done), the README Handoff row and "Known gaps" (official form, not fallback), and the `CLAUDE.md` backlog item 1(a).
