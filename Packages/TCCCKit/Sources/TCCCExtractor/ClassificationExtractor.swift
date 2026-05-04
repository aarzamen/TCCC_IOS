// ClassificationExtractor
//
// Faithful Swift port of `_extract_classification` AND `infer_classification`
// from /Users/ama/TCCC_FEB_2026/src/state.py:
//
//   - `_extract_classification`  : lines 822–855
//   - `infer_classification`     : lines 931–1028
//   - classification_patterns    : lines 451–457
//
// The Python prototype splits these into two methods called from different
// places (per-sentence vs. final-pass). The Swift port keeps both code paths
// inside one ExtractorPass:
//
//   - **Explicit path**: when the sentence text directly mentions a triage
//     category ("urgent", "priority patient", "routine casualty", "walking
//     wounded", "expectant"), the matching `Classification` is written.
//   - **Inferred path**: when explicit text is absent OR the sentence has no
//     classification language, the pass falls through to the same vital +
//     intervention heuristics Python's `infer_classification` uses.
//
// The Python design has the explicit pass run on every sentence (overwriting
// freely) and the inference pass run once at the end via
// `finalize_classifications` (only if classification is unset). The Swift
// engine's per-sentence loop should call this extractor like every other,
// and an explicit-set-from-sentence wins over an inferred classification.
// To preserve that ordering across the iOS engine pipeline:
//
//   - explicit match in the sentence  -> always overwrites
//   - no explicit match               -> recompute inference; if it differs
//                                        from the current value (or the
//                                        current value is nil), set it
//
// This mirrors the behaviour Python achieves by running explicit per-sentence
// and inference once at finalize: explicit findings dominate, but inference
// fills the gap when nothing was said.
//
// Negation handling (state.py:822–854):
//
//   `_extract_classification` runs its own per-sentence negation pre-pass
//   for the word "urgent" so that "nothing urgent, walking wounded" does
//   not classify as Urgent. We mirror that exactly with `NegationDetector`
//   instead of the engine-wide `context.isNegated`, because Python checks
//   the very specific pattern "negation marker + 'urgent'" rather than any
//   negation marker in the sentence (e.g. "denies pain, this is urgent" is
//   tagged isNegated=true but Python would still classify Urgent here).
//
// Foundation only — no SwiftUI, UIKit, Combine, or external deps.

import Foundation
import TCCCDomain

public struct ClassificationExtractor: ExtractorPass {

    // MARK: - Compiled patterns

    /// Ordered classification patterns, mirroring `state.py:451–457`. Order
    /// matters: more specific patterns first ("urgent surgical" before
    /// bare "urgent").
    private let urgentSurgicalRegex: NSRegularExpression
    private let urgentRegex: NSRegularExpression
    private let priorityRegex: NSRegularExpression
    private let routineRegex: NSRegularExpression
    private let expectantRegex: NSRegularExpression

    /// Lower-acuity overrides (`state.py:833–834`).
    private let explicitRoutineRegex: NSRegularExpression
    private let explicitPriorityRegex: NSRegularExpression

    private let negationDetector: NegationDetector

    public init() {
        self.urgentSurgicalRegex = try! NSRegularExpression(
            pattern: "urgent\\s*surgical|needs?\\s*surgery",
            options: [.caseInsensitive])
        self.urgentRegex = try! NSRegularExpression(
            pattern: "\\burgent\\b",
            options: [.caseInsensitive])
        self.priorityRegex = try! NSRegularExpression(
            pattern: "\\bpriority\\b|priority\\s*patient",
            options: [.caseInsensitive])
        self.routineRegex = try! NSRegularExpression(
            pattern: "\\broutine\\b|walking\\s*wounded",
            options: [.caseInsensitive])
        self.expectantRegex = try! NSRegularExpression(
            pattern: "\\bexpectant\\b",
            options: [.caseInsensitive])

        // For lower-acuity override of negated urgent (state.py:833–834).
        // Note the Python `_explicit_priority` pattern uses a negative
        // lookahead "(?!\\s+patient\\s+(?:is|was))" — this is not actually
        // load-bearing for any current scenario fixture, but mirroring it
        // verbatim keeps behavioural parity.
        self.explicitRoutineRegex = try! NSRegularExpression(
            pattern: "\\broutine\\b|walking\\s+wounded",
            options: [.caseInsensitive])
        self.explicitPriorityRegex = try! NSRegularExpression(
            pattern: "\\bpriority\\b(?!\\s+patient\\s+(?:is|was))",
            options: [.caseInsensitive])

        self.negationDetector = NegationDetector()
    }

    // MARK: - ExtractorPass

    public func apply(
        _ state: PatientState, context: ExtractionContext
    ) -> PatientState {
        let sentence = context.sentence

        // ---- Explicit classification (state.py:822–855) -----------------
        //
        // Run the negation pre-pass for "urgent" (state.py:838).
        let urgentNegated = negationDetector.hasNegatedFinding(
            in: sentence, finding: "urgent")
        let explicitRoutine = hasMatch(sentence, regex: explicitRoutineRegex)
        let explicitPriority = hasMatch(sentence, regex: explicitPriorityRegex)

        // Walk patterns in priority order; first hit wins.
        for (regex, classification) in [
            (urgentSurgicalRegex, Classification.urgentSurgical),
            (urgentRegex,         Classification.urgent),
            (priorityRegex,       Classification.priority),
            (routineRegex,        Classification.routine),
            (expectantRegex,      Classification.expectant),
        ] {
            guard hasMatch(sentence, regex: regex) else { continue }

            if (classification == .urgent || classification == .urgentSurgical)
                && urgentNegated {
                // "nothing urgent, walking wounded" path (state.py:846–852).
                if explicitRoutine {
                    var updated = state
                    updated.classification = .routine
                    return updated
                } else if explicitPriority {
                    var updated = state
                    updated.classification = .priority
                    return updated
                }
                // Negated urgent with no lower-acuity override — do nothing
                // (fall through to inference, mirroring Python's `return`
                // without setting classification).
                return inferIfMissing(state)
            }

            var updated = state
            updated.classification = classification
            return updated
        }

        // ---- Inferred classification (state.py:931–1028) ----------------
        //
        // No explicit text matched. Recompute inference; if classification
        // is currently nil OR the inference is non-PENDING, set it.
        return inferIfMissing(state)
    }

    // MARK: - Inference

    /// Wrap `infer` so it only writes when the slot is empty. Mirrors the
    /// `finalize_classifications` guard at state.py:1100–1102:
    ///
    ///     if not patient.classification or patient.classification == "PENDING":
    ///         patient.classification = self.infer_classification(patient)
    private func inferIfMissing(_ state: PatientState) -> PatientState {
        if state.classification != nil { return state }
        guard let inferred = infer(state) else { return state }
        var updated = state
        updated.classification = inferred
        return updated
    }

    /// Direct port of `state.py:infer_classification` (lines 931–1028).
    /// Returns nil for the Python "PENDING" sentinel — Swift uses optional
    /// `Classification?` instead of a magic string.
    public func infer(_ patient: PatientState) -> Classification? {
        let march = patient.march
        let v = patient.vitals

        // Vitals (already parsed by VitalsExtractor — direct ints, no string
        // munging needed unlike the Python helpers).
        let hr = v.hr
        let bpSys = v.bp?.systolic
        let rr = v.rr
        let spo2 = v.spo2
        let gcs = v.gcs

        // ---- URGENT SURGICAL (state.py:952–969) -------------------------
        let urgentSurgical: Bool = {
            // (a) Unresponsive + airway or respiration intervention.
            if let consciousness = march.consciousness?.lowercased(),
               consciousness == "unresponsive",
               (march.airwayIntervention != nil ||
                march.respirationIntervention != nil) {
                return true
            }
            // (b) Pneumothorax with chest seal.
            if let resp = march.respirationStatus?.lowercased(),
               resp.contains("pneumothorax"),
               march.respirationIntervention != nil {
                return true
            }
            // (c) Bilateral hemorrhage location.
            if let loc = march.hemorrhageLocation?.lowercased(),
               loc.contains("bilateral") {
                return true
            }
            // (d) Surgical airway (cric).
            if let aw = march.airwayIntervention?.lowercased(),
               aw.contains("cric") {
                return true
            }
            // (e) Severe TBI (GCS ≤ 8).
            if let g = gcs, g <= 8 {
                return true
            }
            return false
        }()

        if urgentSurgical {
            return .urgentSurgical
        }

        // ---- URGENT (state.py:971–992) ----------------------------------
        let urgent: Bool = {
            // (a) Tourniquet.
            if let hi = march.hemorrhageIntervention?.lowercased(),
               hi.contains("tourniquet") {
                return true
            }
            // (b) Tachycardia HR > 100.
            if let h = hr, h > 100 { return true }
            // (c) Hypotension SBP < 100.
            if let s = bpSys, s < 100 { return true }
            // (d) Airway intervention (NPA, etc.).
            if march.airwayIntervention != nil { return true }
            // (e) Respiratory distress (RR > 24 or < 10).
            if let r = rr, (r > 24 || r < 10) { return true }
            // (f) Hypoxia (SpO2 < 94).
            if let s = spo2, s < 94 { return true }
            // (g) Altered mental status (Voice or Pain).
            if let consciousness = march.consciousness?.lowercased(),
               consciousness == "voice" || consciousness == "pain" {
                return true
            }
            // (h) Femur fracture.
            for inj in patient.injuries {
                if inj.lowercased().contains("femur") { return true }
            }
            return false
        }()

        if urgent {
            return .urgent
        }

        // ---- PRIORITY (state.py:994–1006) -------------------------------
        let priority: Bool = {
            if march.hemorrhageIdentified, march.hemorrhageEffective == true {
                return true
            }
            if let h = hr, h >= 90 && h <= 100 { return true }
            if march.hemorrhageLocation != nil,
               let consciousness = march.consciousness?.lowercased(),
               consciousness == "alert" {
                return true
            }
            return false
        }()

        if priority {
            return .priority
        }

        // ---- ROUTINE (state.py:1008–1022) -------------------------------
        let consciousnessAlert =
            (march.consciousness?.lowercased() == "alert")
        let noMajorIntervention =
            (march.hemorrhageIntervention == nil) &&
            (march.airwayIntervention == nil) &&
            (march.respirationIntervention == nil)
        // "(not hr or (60 <= hr <= 100))" — Python truthy nil = no constraint.
        let stableHR: Bool = {
            guard let h = hr else { return true }
            return (h >= 60 && h <= 100)
        }()
        let stableBP: Bool = {
            guard let s = bpSys else { return true }
            return s >= 100
        }()

        if consciousnessAlert && noMajorIntervention && stableHR && stableBP {
            return .routine
        }

        // ---- Default Priority if any findings (state.py:1024–1026) ------
        if march.hemorrhageIdentified ||
            march.airwayStatus != nil ||
            march.respirationStatus != nil {
            return .priority
        }

        // Nothing — Python returns "PENDING"; Swift returns nil.
        return nil
    }

    // MARK: - Helpers

    private func hasMatch(_ text: String, regex: NSRegularExpression) -> Bool {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: fullRange) != nil
    }
}
