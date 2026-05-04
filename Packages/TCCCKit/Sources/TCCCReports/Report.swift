// Report
//
// Output type for the fallback report generators in TCCCReports. This module
// only ports the *state-derived fallback* path from
// /Users/ama/TCCC_FEB_2026/src/reports.py — the SLM validators
// (`validate_medevac_against_state`, `validate_zmist_against_state`) are
// intentionally deferred until the on-device LLM integration phase lands. When
// SLM output exists, validators will clean it up; until then `MedevacGenerator`
// and `ZMISTGenerator` produce a valid report directly from
// `PatientStateEngine` output.
//
// `isFallback` exposes that distinction at the API boundary so the UI can
// surface the "STATE-DERIVED FALLBACK, SLM UNAVAILABLE" banner.
//
// Foundation only.

import Foundation

/// A generated tactical report (9-Line MEDEVAC or ZMIST).
public struct Report: Sendable, Equatable, Codable {

    /// Discriminator for which report shape is contained in `formattedText`.
    public enum Kind: String, Sendable, Codable, Equatable, CaseIterable {
        /// 9-Line MEDEVAC request.
        case nineLine
        /// ZMIST casualty report (one or more patients).
        case zmist
    }

    /// Which report this is.
    public let kind: Kind

    /// Plain-text body, ready for display, copy/paste, or export.
    public let formattedText: String

    /// When the report was generated (used for headers / file naming downstream).
    public let generatedAt: Date

    /// True until SLM-validated reports ship — see file header comment.
    public let isFallback: Bool

    public init(
        kind: Kind,
        formattedText: String,
        generatedAt: Date,
        isFallback: Bool
    ) {
        self.kind = kind
        self.formattedText = formattedText
        self.generatedAt = generatedAt
        self.isFallback = isFallback
    }
}
