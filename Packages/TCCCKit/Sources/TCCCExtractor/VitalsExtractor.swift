// VitalsExtractor
//
// Swift port of `_extract_vitals` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 799–820), plus the four
// numeric vital-sign regex patterns defined at lines 442–448:
//
//     vitals_patterns = {
//         "hr":   re.compile(r"(?:heart\s*rate|hr|pulse)\s*(?:is\s*|of\s*)?(\d+)", re.I),
//         "bp":   re.compile(r"(?:blood\s*pressure|bp)\s*(?:is\s*)?(\d+)\s*(?:over|/)\s*(\d+)", re.I),
//         "spo2": re.compile(r"(?:pulse\s*ox|spo2|sat|o2\s*sat)\s*(?:is\s*)?(\d+)\s*%?", re.I),
//         "rr":   re.compile(r"(?:respiratory\s*rate|rr)\s*(?:is\s*|looks?\s*(?:about\s*)?)?(\d+)", re.I),
//     }
//
// This pass operates on `context.sentence`, which the engine has already
// normalised via `SpokenNumberNormalizer` — so spoken forms like
// "heart rate one ten" arrive here as "heart rate 110" and the digit-only
// regexes are sufficient.
//
// Narration is anchored to explicit vital names and allowed connectives.
// Latest affirmed, in-range readings replace earlier readings, including RR.
// Negation stays within a clause; questions and goals are not observations.
// RespirationExtractor shares the same RR parser to avoid a second path that
// bypasses these evidence checks. GCS remains in HeadHypothermiaExtractor.

import Foundation
import TCCCDomain

public struct VitalsExtractor: ExtractorPass {

    // MARK: - Compiled regex patterns

    private let hrRegex: NSRegularExpression
    private let bpRegex: NSRegularExpression
    private let spo2Regex: NSRegularExpression
    private let rrRegex: NSRegularExpression

    // MARK: - Field-local affirmation vocabulary

    /// The stated number is denied, not observed ("HR is not 120",
    /// "no heart rate 120"). "nor" is inherently negative on its own.
    private static let negationCues: Set<String> = [
        "no", "not", "nor", "without", "denies", "denied", "negative",
        "absent", "cannot", "can't", "unable", "never", "lost",
    ]

    /// The stated number is a goal / plan / condition, not an observation
    /// ("target heart rate 100", "if HR 100", "aim for oxygen saturation 97").
    private static let goalCues: Set<String> = [
        "target", "targeting", "goal", "goals", "aim", "aiming", "if",
        "unless", "would", "could", "may", "might", "keep", "keeping", "maintain", "maintaining", "should",
        "want", "wants", "titrate", "until", "plan", "planned", "planning",
    ]

    /// Coordinating words that close the preceding clause's negation scope.
    /// "or" is deliberately absent so denial carries across it.
    private static let scopeClosers: Set<String> = ["but", "then"]

    public init() {
        // Connective words accepted between a vital-sign keyword and its
        // number. A whitelist (rather than "any word") so negation and goal
        // words can never be skipped over on the way to a number.
        let gapWord =
            "(?:is|are|was|were|of|at|about|around|approximately|roughly|" +
            "now|currently|still|down|up|to|reading|read|came|come|in|" +
            "looks?|looking|holding|steady|fast|slow|shallow|labored|" +
            "laboured|weak|strong|thready|regular|irregular|rapid)"
        let gap = "(?:[\\s,]+\(gapWord)\\b)*[\\s,]*"

        // Heart rate. Group 1 = numeric value.
        let hrPattern =
            "\\b(?:heart\\s*rate|pulse\\s*rate|hr|pulse)\(gap)(\\d+)"

        // Blood pressure. Group 1 = systolic, group 2 = diastolic, group 3 =
        // optional palpated marker.
        let bpPattern =
            "\\b(?:blood\\s*pressure|bp)\(gap)" +
            "(\\d+)\\s*(?:over|/)\\s*(\\d+)" +
            "(?:\\s*(?:/\\s*)?(p(?:alp(?:ated)?)?))?\\b"

        // SpO2 / pulse-ox / (oxygen) sat(uration). Group 1 = numeric value.
        // Bare "sat" retains the narrow legacy gap: "patient sat up at 3"
        // describes posture, not an oxygen measurement.
        let satGap = #"\s*(?:(?:is|was|of|at|around|reading|came)\s*)?"#
        let spo2Pattern =
            "(?:\\b(?:pulse\\s*ox(?:imetry)?|spo2|" +
            "o2\\s*sat(?:uration)?s?|oxygen\\s*sat(?:uration)?s?|" +
            "saturations?|sats)\(gap)|\\bsat\(satGap))" +
            "(\\d+)\\s*(?:%|percent)?"

        // Respiratory rate / respirations. Group 1 = numeric value.
        let rrPattern =
            "\\b(?:respiratory\\s*rate|resp\\s*rate|respirations?|rr)" +
            "\(gap)(\\d+)"

        // Force-unwraps are safe: these are static literals validated by the
        // test suite. A failure here is a programmer error.
        self.hrRegex = try! NSRegularExpression(
            pattern: hrPattern, options: [.caseInsensitive])
        self.bpRegex = try! NSRegularExpression(
            pattern: bpPattern, options: [.caseInsensitive])
        self.spo2Regex = try! NSRegularExpression(
            pattern: spo2Pattern, options: [.caseInsensitive])
        self.rrRegex = try! NSRegularExpression(
            pattern: rrPattern, options: [.caseInsensitive])
    }

    // MARK: - ExtractorPass

    public func apply(
        _ state: PatientState, context: ExtractionContext
    ) -> PatientState {
        // Negation is handled per candidate match rather than by refusing
        // the whole sentence, so an
        // unrelated "No allergies" cannot swallow "heart rate is 110".
        let sentence = context.sentence

        // Parse each vital. nil means "no affirmed in-range match".
        let newHR = lastAffirmedInt(
            in: sentence, regex: hrRegex, validRange: Vitals.hrRange)
        let newBP = lastAffirmedBP(in: sentence)
        let newSpO2 = lastAffirmedInt(
            in: sentence, regex: spo2Regex, validRange: Vitals.spo2Range)
        let newRR = respiratoryRate(in: sentence)

        let rrToWrite = newRR ?? state.vitals.rr

        // No-op short-circuit: if no field changed, return state unchanged so
        // the engine can detect no-progress passes cheaply.
        if newHR == nil && newBP == nil && newSpO2 == nil &&
            rrToWrite == state.vitals.rr {
            return state
        }

        var updated = state
        // Re-build Vitals so range validation runs (per Vitals.swift contract).
        updated.vitals = Vitals(
            hr: newHR ?? state.vitals.hr,
            bp: newBP ?? state.vitals.bp,
            spo2: newSpO2 ?? state.vitals.spo2,
            rr: rrToWrite,
            gcs: state.vitals.gcs,
            temperatureCelsius: state.vitals.temperatureCelsius,
            capillaryRefillSeconds: state.vitals.capillaryRefillSeconds
        )
        return updated
    }

    // MARK: - Per-vital matchers

    /// Latest affirmed, in-range integer match for `regex` in `text`
    /// (capture group 1). Out-of-range candidates are skipped so a junk
    /// reading never displaces an earlier valid one.
    private func lastAffirmedInt(
        in text: String,
        regex: NSRegularExpression,
        validRange: ClosedRange<Int>
    ) -> Int? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result: Int? = nil
        for m in regex.matches(in: text, options: [], range: fullRange) {
            guard m.numberOfRanges > 1 else { continue }
            let r = m.range(at: 1)
            guard r.location != NSNotFound,
                  let value = Int(nsText.substring(with: r)),
                  validRange.contains(value),
                  isAffirmed(keywordStart: m.range.location, in: nsText)
            else { continue }
            result = value
        }
        return result
    }

    /// Latest affirmed blood-pressure match, with the legacy palpated
    /// suffix behaviour preserved.
    private func lastAffirmedBP(in text: String) -> BloodPressure? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result: BloodPressure? = nil
        for m in bpRegex.matches(in: text, options: [], range: fullRange) {
            guard m.numberOfRanges >= 3 else { continue }
            let sysRange = m.range(at: 1)
            let diaRange = m.range(at: 2)
            guard sysRange.location != NSNotFound,
                  diaRange.location != NSNotFound,
                  let sys = Int(nsText.substring(with: sysRange)),
                  let dia = Int(nsText.substring(with: diaRange)),
                  isAffirmed(keywordStart: m.range.location, in: nsText)
            else { continue }

            // Group 3 is the optional palpated marker.
            var palpated = false
            if m.numberOfRanges >= 4 {
                let palpRange = m.range(at: 3)
                if palpRange.location != NSNotFound {
                    palpated = !nsText.substring(with: palpRange).isEmpty
                }
            }
            result = BloodPressure(
                systolic: sys, diastolic: dia, palpated: palpated)
        }
        return result
    }

    // MARK: - Field-local affirmation

    /// Negation does not expire after an arbitrary word count or "and/or".
    /// Commas and explicit clause transitions delimit unrelated denials.
    /// Goals/questions conservatively govern the sentence, even across a colon
    /// or comma. Mixed plans and observations may therefore need separate lines.
    private func isAffirmed(keywordStart: Int, in nsText: NSString) -> Bool {
        let text = nsText as String
        guard !text.contains("?") else { return false }
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" })
        guard !words.contains(where: { Self.goalCues.contains(String($0)) }) else { return false }
        let prefix = nsText.substring(to: keywordStart)
        let tokens = prefix.replacingOccurrences(of: "’", with: "'").split(whereSeparator: { $0.isWhitespace })
        for raw in tokens.reversed() {
            let token = String(raw)
            if let last = token.last, ",;.!?".contains(last) { break }
            let word = token.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if Self.negationCues.contains(word) { return false }
            if Self.scopeClosers.contains(word) { break }
        }
        return true
    }

    /// Shared with the respiration pass so numeric RR and derived status use
    /// exactly the same observation and range checks as the vital-sign pass.
    func respiratoryRate(in text: String) -> Int? {
        lastAffirmedInt(in: text, regex: rrRegex, validRange: Vitals.rrRange)
    }
}
