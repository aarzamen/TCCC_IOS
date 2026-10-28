#!/usr/bin/env python3
"""Turn the official fillable DD Form 1380 (JUL 2025) into the app's fill template.

The published file (esd.whs.mil, SHA-256 pinned in the repair tool) is
damaged: it was optimized after encryption, so no reader except Adobe's can
draw it (`tools/repair_dd1380_jul2025.py` explains and repairs it). Even
repaired, Apple PDFKit draws its pages blank. This tool therefore:

- refuses any source other than the inspected one (SHA-256 pin);
- repairs it, then redraws both pages with poppler's `pdftocairo -pdf`, which
  PDFKit draws correctly, and puts that artwork under the form's own widgets
  (same page size, same coordinates);
- asserts the page position of key fields (verified 2026-10-28 by drawing every
  field's name onto a render and reading it against the print);
- renames every field to the app's flat names (`FIELD_MAP`, the same names the
  JUN 2014 template used); body-diagram boxes become `body_<original>`;
- turns drop-down fields into plain text fields (routes such as IO are not in
  the official list; the app flattens the form anyway) and removes length
  limits, which would silently cut values;
- sets Arial text appearances, as on the JUN 2014 template;
- writes the template PDF and a JSON manifest of the new names.

Run (pypdf and cryptography are tool-only dependencies, never shipped;
`pdftocairo` comes from Homebrew's poppler):
    uv run --python 3.12 --with pypdf --with cryptography python -I \
        tools/prepare_dd1380_template.py --source ~/Desktop/dd1380-2025.pdf \
        --out-dir TCCC_IOS/Resources/DD1380
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, DictionaryObject, NameObject, NumberObject, TextStringObject

sys.path.insert(0, str(Path(__file__).resolve().parent))
from repair_dd1380_jul2025 import repair  # noqa: E402

TEMPLATE_NAME = "DD1380_JUL2025_template.pdf"
MANIFEST_NAME = "DD1380_JUL2025_fields.json"
TEXT_DA = "/ArialMT 9.00 Tf 0 g"
NOTES_DA = "/ArialMT 7.00 Tf 0 g"
CHOICE_DA = "/ArialMT 8.00 Tf 0 g"

# (page, original terminal name) -> new name.
FIELD_MAP = {
    (0, "roster[0]"): "br_number",
    (0, "evac_urgent[0]"): "evac_urgent",
    (0, "evac_priority[0]"): "evac_priority",
    (0, "evac_routine[0]"): "evac_routine",
    (0, "name[0]"): "name",
    (0, "last4[0]"): "last4",
    (0, "male[0]"): "sex_m",
    (0, "female[0]"): "sex_f",
    (0, "date[0]"): "date",
    (0, "time[0]"): "time",
    (0, "service[0]"): "service",
    (0, "unit[0]"): "unit",
    (0, "allergies[0]"): "allergies",
    (0, "mechanism_artillery[0]"): "moi_artillery",
    (0, "mechanism_blunt[0]"): "moi_blunt",
    (0, "mechanism_burn[0]"): "moi_burn",
    (0, "mechanism_fall[0]"): "moi_fall",
    (0, "mechanism_grenade[0]"): "moi_grenade",
    (0, "mechanism_gsw[0]"): "moi_gsw",
    (0, "mechanism_ied[0]"): "moi_ied",
    (0, "mechanism_landmine[0]"): "moi_landmine",
    (0, "mechanism_mvc[0]"): "moi_mvc",
    (0, "mechanism_rpg[0]"): "moi_rpg",
    (0, "mechanism_other[0]"): "moi_other",
    (0, "mechanism_specify[0]"): "moi_other_text",
    (0, "r_arm_type[0]"): "tq_r_arm_type",
    (0, "r_arm_time[0]"): "tq_r_arm_time",
    (0, "r_leg_type[0]"): "tq_r_leg_type",
    (0, "r_leg_time[0]"): "tq_r_leg_time",
    (0, "l_arm_type[0]"): "tq_l_arm_type",
    (0, "l_arm_time[0]"): "tq_l_arm_time",
    (0, "l_leg_type[0]"): "tq_l_leg_type",
    (0, "l_leg_time[0]"): "tq_l_leg_time",
    (1, "roster[0]"): "br_number_back",
    (1, "evac_urgent[0]"): "evac_urgent_back",
    (1, "evac_priority[0]"): "evac_priority_back",
    (1, "evac_routine[0]"): "evac_routine_back",
    (1, "treatment_C_TQ_Extremity[0]"): "tq_extremity",
    (1, "treatment_C_TQ_Junctional[0]"): "tq_junctional",
    (1, "treatment_C_TQ_Truncal[0]"): "tq_truncal",
    (1, "treatment_C_TQ_type[0]"): "tq_type_text",
    (1, "treatment_C_Dressing_Hemostatic[0]"): "dressing_hemostatic",
    (1, "treatment_C_Dressing_Pressure[0]"): "dressing_pressure",
    (1, "treatment_C_Dressing_Other[0]"): "dressing_other",
    (1, "treatment_C_Dressing_type[0]"): "dressing_type_text",
    (1, "treatment_A_Intact[0]"): "airway_intact",
    (1, "treatment_A_NPA[0]"): "airway_npa",
    (1, "treatment_A_CRIC[0]"): "airway_cric",
    (1, "treatment_A_ET-Tube[0]"): "airway_et_tube",
    (1, "treatment_A_SGA[0]"): "airway_sga",
    (1, "treatment_A_type[0]"): "airway_type_text",
    (1, "treatment_B_O2[0]"): "breathing_o2",
    (1, "treatment_B_NeedleD[0]"): "breathing_needle_d",
    (1, "treatment_B_Chest-Tube[0]"): "breathing_chest_tube",
    (1, "treatment_B_ChestSeal[0]"): "breathing_chest_seal",
    (1, "treatment_B_type[0]"): "breathing_type_text",
    (1, "treatment_other_CombatPillPack[0]"): "other_pill_pack",
    (1, "treatment_other_EyeShield[0]"): "other_eye_shield",
    (1, "treatment_other_R[0]"): "other_eye_shield_r",
    (1, "treatment_other_L[0]"): "other_eye_shield_l",
    (1, "treatment_other_Splint[0]"): "other_splint",
    (1, "treatment_other_HypothermiaPrevention[0]"): "other_hypothermia",
    (1, "treatment_other_type[0]"): "other_hypothermia_type",
    (1, "notes[0]"): "notes",
    (1, "firstResponder_name[0]"): "responder_name",
    (1, "firstResponder_last4[0]"): "responder_last4",
}
for n in range(1, 5):
    FIELD_MAP.update({
        (0, f"time{n}[0]"): f"vitals{n}_time",
        (0, f"pulse{n}[0]"): f"vitals{n}_pulse",
        (0, f"bloodPressureA{n}[0]"): f"vitals{n}_sbp",
        (0, f"bloodPressureB{n}[0]"): f"vitals{n}_dbp",
        (0, f"respRate{n}[0]"): f"vitals{n}_rr",
        (0, f"o2sat{n}[0]"): f"vitals{n}_spo2",
        (0, f"avpu{n}[0]"): f"vitals{n}_avpu",
        (0, f"pain{n}[0]"): f"vitals{n}_pain",
    })
for prefix, new, rows, amount in (("treatment_C_Fluid", "fluid", 2, "Volume"),
                                   ("treatment_C_BloodProduct", "blood", 2, "Volume"),
                                   ("treatment_MEDS_Analgesic", "analgesic", 3, "Dose"),
                                   ("treatment_MEDS_Antibiotic", "antibiotic", 2, "Dose"),
                                   ("treatment_MEDS_Other", "othermed", 2, "Dose")):
    for n in range(1, rows + 1):
        FIELD_MAP.update({
            (1, f"{prefix}_Name{n}[0]"): f"{new}{n}_name",
            (1, f"{prefix}_{amount}{n}[0]"): f"{new}{n}_{amount.lower()}",
            (1, f"{prefix}_Route{n}[0]"): f"{new}{n}_route",
            (1, f"{prefix}_Time{n}[0]"): f"{new}{n}_time",
        })

# Key fields pinned to where they are printed: (page, original) -> (x0, top) in
# points from the top-left corner of the page.
POSITION_PINS = {
    (0, "male[0]"): (69, 124),                     # "SEX: [ ] M"
    (0, "female[0]"): (104, 124),                  # "[ ] F"
    (0, "mechanism_artillery[0]"): (44, 179),
    (0, "mechanism_gsw[0]"): (314, 179),
    (0, "r_arm_type[0]"): (77, 252),
    (0, "l_leg_time[0]"): (253, 439),
    (0, "bloodPressureA1[0]"): (163, 515),         # systolic, left of the printed "/"
    (0, "bloodPressureB1[0]"): (196, 515),         # diastolic, right of it
    (0, "pain4[0]"): (339, 576),
    (1, "treatment_C_TQ_Truncal[0]"): (215, 108),
    (1, "treatment_C_Dressing_Pressure[0]"): (184, 123),
    (1, "treatment_A_CRIC[0]"): (139, 139),
    (1, "treatment_MEDS_Analgesic_Name1[0]"): (132, 284),
    (1, "treatment_MEDS_Other_Time2[0]"): (348, 395),
    (1, "treatment_other_type[0]"): (235, 434),    # Hypothermia-Prevention "Type:"
    (1, "notes[0]"): (33, 468),
}
PIN_TOLERANCE = 2.0
# Entries a widget may inherit from its parent field; copied before the parent is dropped.
INHERITABLE = ("/FT", "/Ff", "/DA", "/Q")


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def type1_font(base_font, encoding=True):
    font = DictionaryObject({
        NameObject("/Type"): NameObject("/Font"),
        NameObject("/Subtype"): NameObject("/Type1"),
        NameObject("/BaseFont"): NameObject(base_font),
    })
    if encoding:
        font[NameObject("/Encoding")] = NameObject("/WinAnsiEncoding")
    return font


def redraw(repaired: Path, artwork: Path):
    pdftocairo = shutil.which("pdftocairo")
    if pdftocairo is None:
        fail("pdftocairo not found (brew install poppler)")
    subprocess.run([pdftocairo, "-pdf", str(repaired), str(artwork)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        repaired, artwork_path = Path(tmp) / "repaired.pdf", Path(tmp) / "artwork.pdf"
        try:
            repair(args.source.expanduser(), repaired)
        except ValueError as error:
            fail(f"{error}; re-inspect field positions before changing the pin")
        redraw(repaired, artwork_path)
        writer = PdfWriter(clone_from=PdfReader(repaired))
        artwork = PdfReader(artwork_path)

        if len(artwork.pages) != 2 or len(writer.pages) != 2:
            fail("expected two pages in both the form and its redrawn artwork")
        for page, art in zip(writer.pages, artwork.pages):
            if [float(v) for v in page.mediabox] != [float(v) for v in art.mediabox]:
                fail(f"artwork page size {art.mediabox} differs from the form's {page.mediabox}")
            page[NameObject("/Contents")] = art.raw_get("/Contents").clone(writer)
            page[NameObject("/Resources")] = art.raw_get("/Resources").clone(writer)
            if "/Group" in art:
                page[NameObject("/Group")] = art.raw_get("/Group").clone(writer)
            if "/StructParents" in page:
                del page["/StructParents"]

        root = writer._root_object
        for key in ("/StructTreeRoot", "/MarkInfo", "/NeedsRendering", "/OpenAction", "/AA"):
            if key in root:
                del root[key]
        acroform = root["/AcroForm"]
        for key in ("/XFA", "/NeedAppearances"):
            if key in acroform:
                del acroform[key]
        acroform[NameObject("/DR")] = DictionaryObject({NameObject("/Font"): DictionaryObject({
            NameObject("/ArialMT"): writer._add_object(type1_font("/ArialMT")),
            NameObject("/Helv"): writer._add_object(type1_font("/Helvetica")),
            NameObject("/ZaDb"): writer._add_object(type1_font("/ZapfDingbats", encoding=False)),
        })})
        acroform[NameObject("/DA")] = TextStringObject("/Helv 0 Tf 0 g")

        fields, manifest, seen, used = ArrayObject(), [], set(), set()
        for page_index, page in enumerate(writer.pages):
            height = float(page.mediabox.height)
            for ref in page.get("/Annots", []):
                widget = ref.get_object()
                if widget.get("/Subtype") != "/Widget":
                    continue
                if "/T" not in widget:
                    fail(f"widget without a name on page {page_index}")
                # Names are full dotted paths ("form1[0].P1[0].info[0].male[0]"); match the last part.
                original = str(widget["/T"]).rsplit(".", 1)[-1]
                key = (page_index, original)
                if key in seen:
                    fail(f"duplicate field {original} on page {page_index}")
                seen.add(key)
                parent = widget.get("/Parent")
                while parent is not None:
                    parent = parent.get_object()
                    for name in INHERITABLE:
                        if name not in widget and name in parent:
                            widget[NameObject(name)] = parent[name]
                    parent = parent.get("/Parent")
                x0, _, _, y1 = (float(v) for v in widget["/Rect"])
                if key in POSITION_PINS:
                    px, ptop = POSITION_PINS[key]
                    if abs(x0 - px) > PIN_TOLERANCE or abs((height - y1) - ptop) > PIN_TOLERANCE:
                        fail(f"{original} on page {page_index} is at ({x0:.0f}, {height - y1:.0f}), "
                             f"expected ({px}, {ptop})")
                if key in FIELD_MAP:
                    new_name = FIELD_MAP[key]
                elif page_index == 0 and widget.get("/FT") == "/Btn":
                    new_name = "body_" + original.replace("[0]", "")
                else:
                    fail(f"unmapped field {original} on page {page_index}")
                if new_name in used:
                    fail(f"name collision: {new_name}")
                used.add(new_name)

                widget[NameObject("/T")] = TextStringObject(new_name)
                for key_name in ("/Parent", "/TU", "/AA", "/A", "/StructParent"):
                    if key_name in widget:
                        del widget[key_name]
                if widget.get("/FT") == "/Ch":
                    widget[NameObject("/FT")] = NameObject("/Tx")
                    widget[NameObject("/Ff")] = NumberObject(0)
                    widget[NameObject("/DA")] = TextStringObject(CHOICE_DA)
                    # Centered, like the text cells beside it (the drop-downs were left-aligned).
                    widget[NameObject("/Q")] = NumberObject(1)
                    for key_name in ("/Opt", "/TI", "/I", "/V", "/DV"):
                        if key_name in widget:
                            del widget[key_name]
                elif widget.get("/FT") == "/Tx":
                    widget[NameObject("/DA")] = TextStringObject(TEXT_DA)
                if widget.get("/FT") == "/Tx":
                    # /MaxLen silently truncates (the form caps Last 4); the app
                    # shrinks the font to fit instead.
                    for key_name in ("/V", "/DV", "/AP", "/MaxLen"):
                        if key_name in widget:
                            del widget[key_name]
                if new_name == "notes":
                    widget[NameObject("/DA")] = TextStringObject(NOTES_DA)
                    widget[NameObject("/Ff")] = NumberObject(int(widget.get("/Ff", 0)) | 4096)
                if widget.get("/FT") == "/Btn":
                    widget[NameObject("/AS")] = NameObject("/Off")
                    widget[NameObject("/V")] = NameObject("/Off")

                fields.append(ref)
                manifest.append({
                    "name": new_name,
                    "type": "checkbox" if widget["/FT"] == "/Btn" else "text",
                    "page": page_index,
                    "rect": [round(float(v), 1) for v in widget["/Rect"]],
                })

        missing = sorted(new for key, new in FIELD_MAP.items() if key not in seen)
        if missing:
            fail(f"mapped fields not found in source: {missing}")
        acroform[NameObject("/Fields")] = fields

        # Re-clone so only reachable objects are written: the replaced page
        # content (the original drawing and its images) stays behind.
        draft = Path(tmp) / "draft.pdf"
        with draft.open("wb") as stream:
            writer.write(stream)
        args.out_dir.mkdir(parents=True, exist_ok=True)
        with (args.out_dir / TEMPLATE_NAME).open("wb") as stream:
            PdfWriter(clone_from=PdfReader(draft)).write(stream)
    manifest.sort(key=lambda item: item["name"])
    (args.out_dir / MANIFEST_NAME).write_text(json.dumps(manifest, indent=1) + "\n")
    checkboxes = sum(1 for item in manifest if item["type"] == "checkbox")
    print(f"wrote 2 pages, {len(manifest)} fields "
          f"({len(manifest) - checkboxes} text, {checkboxes} checkboxes, 0 XFA) to {args.out_dir}")


if __name__ == "__main__":
    main()
