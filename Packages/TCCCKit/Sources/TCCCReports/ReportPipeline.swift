// ReportPipeline
//
// Convenience layer that runs both fallback generators and returns their
// reports in a stable order. Mirrors the dual-emit behavior of the Python
// `ReportGenerator.save_*` calls in
// /Users/ama/TCCC_FEB_2026/src/reports.py — but stays in-memory; persistence
// to disk is the caller's responsibility on iOS.
//
// Foundation only.

import Foundation
import TCCCDomain

/// Runs both report generators and returns their output. The return order is
/// deterministic: 9-Line first, ZMIST second.
public struct ReportPipeline: Sendable {

    public let medevac: MedevacGenerator
    public let zmist: ZMISTGenerator

    public init(
        medevac: MedevacGenerator = MedevacGenerator(),
        zmist: ZMISTGenerator = ZMISTGenerator()
    ) {
        self.medevac = medevac
        self.zmist = zmist
    }

    /// Returns `[nineLine, zmist]` from the supplied patient lineup.
    public func generateAll(
        from patients: [PatientState],
        at timestamp: Date = Date()
    ) -> [Report] {
        return [
            medevac.generate(from: patients, at: timestamp),
            zmist.generate(from: patients, at: timestamp),
        ]
    }
}
