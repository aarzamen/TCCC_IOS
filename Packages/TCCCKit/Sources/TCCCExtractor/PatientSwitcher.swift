// PatientSwitcher
//
// Faithful Swift port of `_check_new_patient` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 530–567). The Python helper:
//
//     def _check_new_patient(self, text, timestamp):
//         # PATIENT_3 check first (most specific)
//         match = re.search(
//             r"casualty\s*(?:three|3)|third\s*casualty|patient\s*(?:three|3)|"
//             r"moving\s+to\s+(?:casualty|patient)\s*(?:three|3)",
//             text, re.I)
//         if match:
//             self.current_patient_id = "PATIENT_3"
//             ...return
//
//         # PATIENT_2 check
//         match = re.search(
//             r"casualty\s*(?:two|2)|second\s*casualty|patient\s*(?:two|2)|"
//             r"moving\s+to\s+(?:casualty|patient)(?:\s+(?:two|2))?|"
//             r"another\s+(?:patient|casualty)|next\s+(?:patient|casualty)",
//             text, re.I)
//         ...
//
//         # PATIENT_1 check
//         match = re.search(
//             r"casualty\s*(?:one|1)|first\s*casualty|patient\s*(?:one|1)|"
//             r"moving\s+to\s+(?:casualty|patient)\s*(?:one|1)",
//             text, re.I)
//
// We preserve the priority order (3, then 2, then 1) and the exact regex
// alternations. The detector is pure: it returns the new patient ID or nil if
// no switch was indicated. The engine owns the actual `currentPatientID`
// mutation.
//
// Foundation only.

import Foundation

/// Detects patient-switch utterances like "casualty two", "moving to patient 3",
/// "another casualty", etc. Returns the new patient ID, or nil if the sentence
/// does not indicate a switch.
public struct PatientSwitcher: Sendable {

    private let patient3Regex: NSRegularExpression
    private let patient2Regex: NSRegularExpression
    private let patient1Regex: NSRegularExpression

    public init() {
        // Priority order matches Python: PATIENT_3 first (most specific), then
        // PATIENT_2 (which catches the broad "another/next casualty"), then
        // PATIENT_1 (the explicit switch-back).

        let p3 =
            "casualty\\s*(?:three|3)|" +
            "third\\s*casualty|" +
            "patient\\s*(?:three|3)|" +
            "moving\\s+to\\s+(?:casualty|patient)\\s*(?:three|3)"

        let p2 =
            "casualty\\s*(?:two|2)|" +
            "second\\s*casualty|" +
            "patient\\s*(?:two|2)|" +
            "moving\\s+to\\s+(?:casualty|patient)(?:\\s+(?:two|2))?|" +
            "another\\s+(?:patient|casualty)|" +
            "next\\s+(?:patient|casualty)"

        let p1 =
            "casualty\\s*(?:one|1)|" +
            "first\\s*casualty|" +
            "patient\\s*(?:one|1)|" +
            "moving\\s+to\\s+(?:casualty|patient)\\s*(?:one|1)"

        self.patient3Regex = try! NSRegularExpression(
            pattern: p3, options: [.caseInsensitive])
        self.patient2Regex = try! NSRegularExpression(
            pattern: p2, options: [.caseInsensitive])
        self.patient1Regex = try! NSRegularExpression(
            pattern: p1, options: [.caseInsensitive])
    }

    /// Returns the new patient ID ("PATIENT_1", "PATIENT_2", "PATIENT_3") if
    /// the sentence contains a switch utterance, or nil otherwise.
    ///
    /// Mirrors the Python `_check_new_patient` priority: PATIENT_3 wins over
    /// PATIENT_2 wins over PATIENT_1 if multiple cues are present in the same
    /// sentence.
    public func detectSwitch(in text: String) -> String? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if patient3Regex.firstMatch(in: text, options: [], range: fullRange) != nil {
            return "PATIENT_3"
        }
        if patient2Regex.firstMatch(in: text, options: [], range: fullRange) != nil {
            return "PATIENT_2"
        }
        if patient1Regex.firstMatch(in: text, options: [], range: fullRange) != nil {
            return "PATIENT_1"
        }
        return nil
    }
}
