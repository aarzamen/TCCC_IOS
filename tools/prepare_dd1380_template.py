#!/usr/bin/env python3
"""Turn the official fillable DD Form 1380 (JUN 2014) into the app's fill template.

The official form is a LiveCycle hybrid (XFA + AcroForm). Its field names and
tooltips are wrong in places: the box printed "Truncal" is named
`PressureDressing`, the Pressure and Other dressing boxes are `HemoDressing[1]`
and `HemoDressing[2]`, and the three "Type" lines are all `TypeSGA[n]`. This
tool therefore:

- refuses any source other than the inspected one (SHA-256 pin);
- asserts the page position of every field whose name lies;
- renames every field to a flat, honest name (`FIELD_MAP`); body-diagram boxes
  become `body_<original>`;
- turns drop-down fields into plain text fields (routes such as IO are not in
  the official list; the app flattens the form anyway);
- removes the XFA layer, JavaScript and field actions so every reader shows
  the AcroForm values;
- writes the template PDF and a JSON manifest of the new names.

Run (pypdf is a tool-only dependency, never shipped):
    uv run --python 3.12 --with pypdf python -I tools/prepare_dd1380_template.py \
        --source "reference/rubric/TCCC rubrics and guidelines/tccc-card-form-1380-en.pdf" \
        --out-dir TCCC_IOS/Resources/DD1380
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, NameObject, NumberObject, TextStringObject

SOURCE_SHA256 = "bd8949d45ce778bfb6344c79eeba34a131847b123647dfdfa7eb4fe2cf93bbba"
TEMPLATE_NAME = "DD1380_JUN2014_template.pdf"
MANIFEST_NAME = "DD1380_JUN2014_fields.json"
NOTES_DA = "/ArialMT 7.00 Tf 0 g"

# (page, original terminal name) -> new name. Verified on 2026-10-27 by drawing
# each field's name onto a render of the form and reading it against the print.
FIELD_MAP = {
    (0, "BRnumber[0]"): "br_number",
    (0, "A-Urgent[0]"): "evac_urgent",
    (0, "B-Priority[0]"): "evac_priority",
    (0, "C-Routine[0]"): "evac_routine",
    (0, "Name[0]"): "name",
    (0, "Last4SSN[0]"): "last4",
    (0, "GenderM[0]"): "sex_m",
    (0, "GenderF[0]"): "sex_f",
    (0, "Gender[0]"): "gender_label_unused",
    (0, "Date[0]"): "date",
    (0, "Time[0]"): "time",
    (0, "Service[0]"): "service",
    (0, "Unit[0]"): "unit",
    (0, "Allergies[0]"): "allergies",
    (0, "MOIArtillery[0]"): "moi_artillery",
    (0, "MOIBlunt[0]"): "moi_blunt",
    (0, "MOIBurn[0]"): "moi_burn",
    (0, "MOIFall[0]"): "moi_fall",
    (0, "MOIGrenade[0]"): "moi_grenade",
    (0, "MOIGSW[0]"): "moi_gsw",
    (0, "MOIIED[0]"): "moi_ied",
    (0, "MOILandmine[0]"): "moi_landmine",
    (0, "MOIMVC[0]"): "moi_mvc",
    (0, "MOIRPG[0]"): "moi_rpg",
    (0, "MOIOther[0]"): "moi_other",
    (0, "MOIOtherSpecify[0]"): "moi_other_text",
    (0, "TQRUEType[0]"): "tq_r_arm_type",
    (0, "TQRUETime[0]"): "tq_r_arm_time",
    (0, "TQRLEType[0]"): "tq_r_leg_type",
    (0, "TQRLETime[0]"): "tq_r_leg_time",
    (0, "TQLUEType[0]"): "tq_l_arm_type",
    (0, "TQLUETime[0]"): "tq_l_arm_time",
    (0, "TQLLEType[0]"): "tq_l_leg_type",
    (0, "TQLLETime[0]"): "tq_l_leg_time",
    (1, "BRnumber[1]"): "br_number_back",
    (1, "A-Urgent[0]"): "evac_urgent_back",
    (1, "B-Priority[0]"): "evac_priority_back",
    (1, "C-Routine[0]"): "evac_routine_back",
    (1, "ExtremityTQ[0]"): "tq_extremity",
    (1, "JuncTQ[0]"): "tq_junctional",
    (1, "PressureDressing[0]"): "tq_truncal",
    (1, "TypeSGA[1]"): "tq_type_text",
    (1, "HemoDressing[0]"): "dressing_hemostatic",
    (1, "HemoDressing[1]"): "dressing_pressure",
    (1, "HemoDressing[2]"): "dressing_other",
    (1, "TypeSGA[2]"): "dressing_type_text",
    (1, "Intact[0]"): "airway_intact",
    (1, "NPA[0]"): "airway_npa",
    (1, "Cric[0]"): "airway_cric",
    (1, "ETtube[0]"): "airway_et_tube",
    (1, "SGA[0]"): "airway_sga",
    (1, "TypeSGA[0]"): "airway_type_text",
    (1, "O2[0]"): "breathing_o2",
    (1, "NeedleD[0]"): "breathing_needle_d",
    (1, "ChestTube[0]"): "breathing_chest_tube",
    (1, "ChestSeal[0]"): "breathing_chest_seal",
    (1, "TypeChestSeal[0]"): "breathing_type_text",
    (1, "FluidName1[0]"): "fluid1_name",
    (1, "FluidVolume1[0]"): "fluid1_volume",
    (1, "FluidRoute1[0]"): "fluid1_route",
    (1, "FluidTime1[0]"): "fluid1_time",
    (1, "FluidName2[0]"): "fluid2_name",
    (1, "FluidVolume2[0]"): "fluid2_volume",
    (1, "FluidRoute2[0]"): "fluid2_route",
    (1, "FluiTime2[0]"): "fluid2_time",
    (1, "FluidName1[1]"): "blood1_name",
    (1, "FluidVolume1[1]"): "blood1_volume",
    (1, "BPRoute1[0]"): "blood1_route",
    (1, "BPTime1[0]"): "blood1_time",
    (1, "FluidName2[1]"): "blood2_name",
    (1, "FluidVolume2[1]"): "blood2_volume",
    (1, "BPRoute2[0]"): "blood2_route",
    (1, "BPTime2[0]"): "blood2_time",
    (1, "OtherMedName1[0]"): "othermed1_name",
    (1, "OtherMedDose1[0]"): "othermed1_dose",
    (1, "OtherMedRoute1[0]"): "othermed1_route",
    (1, "OtheMedTime1[0]"): "othermed1_time",
    (1, "OtherMedName2[0]"): "othermed2_name",
    (1, "OtherMedDose2[0]"): "othermed2_dose",
    (1, "OtherMedRoute2[0]"): "othermed2_route",
    (1, "OtheMedTime2[0]"): "othermed2_time",
    (1, "PillPack[0]"): "other_pill_pack",
    (1, "EyeShield[0]"): "other_eye_shield",
    (1, "EyeShieldR[0]"): "other_eye_shield_r",
    (1, "EyeShieldL[0]"): "other_eye_shield_l",
    (1, "Splint[0]"): "other_splint",
    (1, "HypoTherm[0]"): "other_hypothermia",
    (1, "HypoThermiaPrevType[0]"): "other_hypothermia_type",
    (1, "Notes[0]"): "notes",
    (1, "FirstRespName[0]"): "responder_name",
    (1, "FirstRespLast4SSN[0]"): "responder_last4",
}
for n in range(1, 5):
    FIELD_MAP.update({
        (0, f"SignTime{n}[0]"): f"vitals{n}_time",
        (0, f"SignPulse{n}[0]"): f"vitals{n}_pulse",
        (0, f"SignSBP{n}[0]"): f"vitals{n}_sbp",
        (0, f"SignDBP{n}[0]"): f"vitals{n}_dbp",
        (0, f"SignRespRate{n}[0]"): f"vitals{n}_rr",
        (0, f"SignOx{n}[0]"): f"vitals{n}_spo2",
        (0, f"SignAVPU{n}[0]"): f"vitals{n}_avpu",
        (0, f"SignPain{n}[0]"): f"vitals{n}_pain",
    })
for n in range(1, 4):
    FIELD_MAP.update({
        (1, f"AnagelsicName{n}[0]"): f"analgesic{n}_name",
        (1, f"AnagelsicDose{n}[0]"): f"analgesic{n}_dose",
        (1, f"AnagelsicRoute{n}[0]"): f"analgesic{n}_route",
        (1, f"AnalgesicTime{n}[0]"): f"analgesic{n}_time",
    })
for n in range(1, 3):
    FIELD_MAP.update({
        (1, f"AntibioticName{n}[0]"): f"antibiotic{n}_name",
        (1, f"AntibioticDose{n}[0]"): f"antibiotic{n}_dose",
        (1, f"AntibioticRoute{n}[0]"): f"antibiotic{n}_route",
        (1, f"AntibioticTime{n}[0]"): f"antibiotic{n}_time",
    })

# Fields whose names lie, pinned to where they are printed: (page, original) ->
# (x0, top) in points from the top-left corner of the page.
POSITION_PINS = {
    (1, "PressureDressing[0]"): (218, 105),   # printed "Truncal"
    (1, "HemoDressing[0]"): (107, 124),       # "Hemostatic"
    (1, "HemoDressing[1]"): (183, 124),       # "Pressure"
    (1, "HemoDressing[2]"): (246, 124),       # "Other"
    (1, "TypeSGA[1]"): (302, 104),            # TQ "Type"
    (1, "TypeSGA[2]"): (302, 123),            # Dressing "Type"
    (1, "TypeSGA[0]"): (302, 143),            # Airway "Type"
    (0, "MOIArtillery[0]"): (44, 175),        # tooltip says "Gun Shot Wound"
    (0, "MOIGSW[0]"): (317, 175),             # tooltip says "Improvised Explosive Device"
}
PIN_TOLERANCE = 2.0


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()

    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
    if digest != SOURCE_SHA256:
        fail(f"source SHA-256 {digest} is not the inspected DD 1380 JUN 2014 ({SOURCE_SHA256}); "
             "re-inspect field positions before changing the pin")

    writer = PdfWriter(clone_from=PdfReader(args.source))
    root = writer._root_object
    acroform = root["/AcroForm"]
    for key in ("/XFA", "/NeedAppearances"):
        if key in acroform:
            del acroform[key]
    for key in ("/NeedsRendering", "/OpenAction", "/AA"):
        if key in root:
            del root[key]
    if "/Names" in root and "/JavaScript" in root["/Names"]:
        del root["/Names"]["/JavaScript"]

    fields, manifest, seen, used = ArrayObject(), [], set(), set()
    for page_index, page in enumerate(writer.pages):
        height = float(page.mediabox.height)
        for ref in page.get("/Annots", []):
            widget = ref.get_object()
            if widget.get("/Subtype") != "/Widget":
                continue
            original = str(widget["/T"])
            key = (page_index, original)
            if key in seen:
                fail(f"duplicate field {original} on page {page_index}")
            seen.add(key)
            x0, _, _, y1 = (float(v) for v in widget["/Rect"])
            if key in POSITION_PINS:
                px, ptop = POSITION_PINS[key]
                if abs(x0 - px) > PIN_TOLERANCE or abs((height - y1) - ptop) > PIN_TOLERANCE:
                    fail(f"{original} on page {page_index} is at ({x0:.0f}, {height - y1:.0f}), "
                         f"expected ({px}, {ptop})")
            if key in FIELD_MAP:
                new_name = FIELD_MAP[key]
            elif widget.get("/FT") == "/Btn":
                new_name = "body_" + original.replace("[0]", "")
            else:
                fail(f"unmapped non-checkbox field {original} on page {page_index}")
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
                for key_name in ("/Opt", "/TI", "/I", "/V", "/DV"):
                    if key_name in widget:
                        del widget[key_name]
            if widget.get("/FT") == "/Tx":
                for key_name in ("/V", "/DV", "/AP"):
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

    args.out_dir.mkdir(parents=True, exist_ok=True)
    with (args.out_dir / TEMPLATE_NAME).open("wb") as stream:
        writer.write(stream)
    manifest.sort(key=lambda item: item["name"])
    (args.out_dir / MANIFEST_NAME).write_text(json.dumps(manifest, indent=1) + "\n")
    checkboxes = sum(1 for item in manifest if item["type"] == "checkbox")
    print(f"wrote {len(writer.pages)} pages, {len(manifest)} fields "
          f"({len(manifest) - checkboxes} text, {checkboxes} checkboxes, 0 XFA) to {args.out_dir}")


if __name__ == "__main__":
    main()
