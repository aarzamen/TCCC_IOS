import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI
import TCCCDomain

// MARK: - Encounter summary lines

/// One row in the Encounter Summary panel.
struct HandoffSummaryLine: Identifiable, Sendable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let isHot: Bool
}

// MARK: - Timeline events

/// One row in the Timeline panel.
struct HandoffTimelineEvent: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let icon: String
    let kindLabel: String
    let detail: String
    let isHot: Bool
}

// MARK: - Static-style helpers

/// Builds the encounter-summary lines from a (possibly nil) patient.
///
/// Missing fields render with em-dashes so the layout stays stable.
@MainActor
enum HandoffSummary {

    static func lines(for patient: PatientState?, casualtyId: String) -> [HandoffSummaryLine] {
        var rows: [HandoffSummaryLine] = []

        // MOI · location · timestamp
        rows.append(
            .init(
                icon: "exclamationmark.octagon",
                label: "MOI",
                value: moiValue(patient),
                isHot: false
            )
        )

        // CRITICAL — derived from classification.
        let classification = patient?.classification
        rows.append(
            .init(
                icon: "exclamationmark.triangle",
                label: "CRITICAL",
                value: criticalValue(for: classification),
                isHot: classification == .urgent || classification == .urgentSurgical
            )
        )

        // CONTROL — hemorrhage intervention.
        rows.append(
            .init(
                icon: "tag",
                label: "CONTROL",
                value: controlValue(patient),
                isHot: false
            )
        )

        // LAST VITALS — compact one-liner.
        rows.append(
            .init(
                icon: "heart",
                label: "LAST VITALS",
                value: vitalsValue(patient),
                isHot: false
            )
        )

        // MEDS — interventions of medication / pain / antibiotic kind.
        rows.append(
            .init(
                icon: "syringe",
                label: "MEDS",
                value: medsValue(patient),
                isHot: false
            )
        )

        // FLUIDS — IV / IO access interventions.
        rows.append(
            .init(
                icon: "drop",
                label: "FLUIDS",
                value: fluidsValue(patient),
                isHot: false
            )
        )

        // PRIORITY — classification + LITTER/AMBULATORY + DUSTOFF requested.
        rows.append(
            .init(
                icon: "antenna.radiowaves.left.and.right",
                label: "PRIORITY",
                value: priorityValue(for: classification),
                isHot: classification == .urgent || classification == .urgentSurgical
            )
        )

        // ETA TO LZ — placeholder (no route data wired yet).
        rows.append(
            .init(
                icon: "mappin.and.ellipse",
                label: "ETA TO LZ",
                value: "—",
                isHot: false
            )
        )

        return rows
    }

    // MARK: Field formatters

    private static func moiValue(_ patient: PatientState?) -> String {
        guard let patient else { return "—" }
        var parts: [String] = []
        if let moi = patient.mechanismOfInjury, !moi.isEmpty {
            parts.append(moi)
        }
        if let loc = patient.march.hemorrhageLocation, !loc.isEmpty {
            parts.append(loc)
        }
        if let ts = patient.timestampFirstMention {
            parts.append(formatTime(Date(timeIntervalSince1970: ts)))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private static func criticalValue(for classification: Classification?) -> String {
        switch classification {
        case .urgent:           "Hemorrhagic shock · class III"
        case .urgentSurgical:   "Surgical · damage control needed"
        case .priority:         "Stable · close monitoring"
        case .routine:          "Stable · ambulatory"
        case .expectant:        "Expectant · comfort care"
        case .none:             "—"
        }
    }

    private static func controlValue(_ patient: PatientState?) -> String {
        guard let patient else { return "—" }
        var parts: [String] = []
        if let intervention = patient.march.hemorrhageIntervention, !intervention.isEmpty {
            parts.append(intervention)
        }
        // First tourniquet timestamp if available.
        if let tq = patient.interventions.first(where: { $0.kind == .tourniquet }) {
            parts.append("@ \(formatTime(tq.timestamp))")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private static func vitalsValue(_ patient: PatientState?) -> String {
        guard let patient else { return "—" }
        let v = patient.vitals
        var parts: [String] = []
        if let hr = v.hr { parts.append("HR \(hr)") }
        if let bp = v.bp {
            let suffix = bp.palpated ? " P" : ""
            parts.append("BP \(bp.systolic)\u{2013}\(bp.diastolic)\(suffix)")
        }
        if let spo2 = v.spo2 { parts.append("SpO\u{2082} \(spo2)%") }
        if let rr = v.rr { parts.append("RR \(rr)") }
        if let gcs = v.gcs { parts.append("GCS \(gcs)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " / ")
    }

    private static func medsValue(_ patient: PatientState?) -> String {
        guard let patient else { return "—" }
        let kinds: Set<InterventionKind> = [.medication, .painManagement, .antibiotic]
        let meds = patient.interventions
            .filter { kinds.contains($0.kind) }
            .map { $0.description }
        return meds.isEmpty ? "—" : meds.joined(separator: " · ")
    }

    private static func fluidsValue(_ patient: PatientState?) -> String {
        guard let patient else { return "—" }
        let kinds: Set<InterventionKind> = [.ivAccess, .ioAccess]
        let fluids = patient.interventions
            .filter { kinds.contains($0.kind) }
            .map { $0.description }
        return fluids.isEmpty ? "—" : fluids.joined(separator: " · ")
    }

    private static func priorityValue(for classification: Classification?) -> String {
        guard let classification else { return "—" }
        let isLitter: Bool
        switch classification {
        case .urgent, .urgentSurgical, .priority, .expectant: isLitter = true
        case .routine: isLitter = false
        }
        let mode = isLitter ? "LITTER" : "AMBULATORY"
        var parts: [String] = [classification.rawValue.uppercased(), mode]
        if classification == .urgent || classification == .urgentSurgical {
            parts.append("DUSTOFF requested")
        }
        return parts.joined(separator: " · ")
    }

    static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Timeline builder

@MainActor
enum HandoffTimeline {

    static func events(for patient: PatientState?, sessionStart: Date, now: Date = Date()) -> [HandoffTimelineEvent] {
        var rows: [HandoffTimelineEvent] = []

        // Synthetic POI marker.
        let poiTimestamp = patient?.timestampFirstMention.map { Date(timeIntervalSince1970: $0) } ?? sessionStart
        rows.append(
            .init(
                timestamp: poiTimestamp,
                icon: "person.crop.circle",
                kindLabel: "POI",
                detail: "Casualty contact",
                isHot: false
            )
        )

        // Map interventions.
        if let patient {
            for intervention in patient.interventions.sorted(by: { $0.timestamp < $1.timestamp }) {
                rows.append(
                    .init(
                        timestamp: intervention.timestamp,
                        icon: icon(for: intervention.kind),
                        kindLabel: kindLabel(for: intervention.kind),
                        detail: intervention.description,
                        isHot: isHot(intervention.kind)
                    )
                )
            }
        }

        // Synthetic 9-Line marker — last row.
        rows.append(
            .init(
                timestamp: now,
                icon: "antenna.radiowaves.left.and.right",
                kindLabel: "9L",
                detail: "MEDEVAC requested",
                isHot: true
            )
        )

        return rows
    }

    static func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func formatElapsed(from start: Date, to now: Date = Date()) -> String {
        let total = max(Int(now.timeIntervalSince(start)), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private static func icon(for kind: InterventionKind) -> String {
        switch kind {
        case .tourniquet:                                   "tag"
        case .pressureDressing, .dressing, .woundCare:      "bandage"
        case .chestSeal, .needleDecompression:              "lungs"
        case .npa, .surgicalAirway:                         "wind"
        case .ivAccess, .ioAccess:                          "drop.fill"
        case .medication, .painManagement, .antibiotic:     "syringe"
        case .splint:                                       "ruler"
        case .hypothermiaPrevention:                        "thermometer.snowflake"
        case .other:                                        "plus.circle"
        }
    }

    private static func kindLabel(for kind: InterventionKind) -> String {
        switch kind {
        case .tourniquet:                       "TQ"
        case .pressureDressing, .dressing:      "DRESSING"
        case .chestSeal:                        "CHEST SEAL"
        case .needleDecompression:              "NDC"
        case .ivAccess:                         "IV"
        case .ioAccess:                         "IO"
        case .medication:                       "MED"
        case .antibiotic:                       "ABX"
        case .painManagement:                   "PAIN"
        case .woundCare:                        "WOUND"
        case .npa:                              "NPA"
        case .surgicalAirway:                   "SURG AW"
        case .splint:                           "SPLINT"
        case .hypothermiaPrevention:            "HYPO"
        case .other:                            "INT"
        }
    }

    private static func isHot(_ kind: InterventionKind) -> Bool {
        switch kind {
        case .tourniquet, .medication, .painManagement, .antibiotic: true
        default: false
        }
    }
}

// MARK: - QR encoding

@MainActor
enum HandoffQR {

    /// Returns the JSON-encoded patient payload ready for QR rendering.
    /// Falls back to a minimal placeholder when no patient exists yet.
    static func payload(for patient: PatientState?) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let patient {
            return (try? encoder.encode(patient)) ?? Data("{}".utf8)
        }
        return Data("{}".utf8)
    }

    /// Estimated KB size of the JSON payload, ceiling-rounded.
    static func payloadKilobytes(for patient: PatientState?) -> Int {
        let bytes = payload(for: patient).count
        return max(1, Int(ceil(Double(bytes) / 1024.0)))
    }

    /// Renders a CIImage QR for the given data. Caller wraps in UIImage/Image.
    static func generateImage(from data: Data, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: nil)
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

// MARK: - Export file builders

@MainActor
enum HandoffExports {

    /// Write the patient JSON to a temp file, return the URL. Suitable for
    /// passing to UIActivityViewController.
    static func writeJSON(for patient: PatientState?, casualtyId: String) -> URL? {
        let data = HandoffQR.payload(for: patient)
        let dir = FileManager.default.temporaryDirectory
        let stamp = Self.timestampString()
        let url = dir.appendingPathComponent("encounter-\(casualtyId)-\(stamp).json")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    /// Build a CSV with one row of current vitals and write to temp.
    /// Phase 1 stub — DD 1380 Section C is rebuilt as a 4-column grid in
    /// Phase 4, at which point this helper will emit the full grid.
    /// Header row + a single timestamped row of the most recent vitals.
    static func writeVitalsCSV(vitals: Vitals?, casualtyId: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let stamp = Self.timestampString()
        let url = dir.appendingPathComponent("vitals-\(casualtyId)-\(stamp).csv")

        var rows: [String] = []
        rows.append("timestamp,hr,sys,dia,spo2,rr")
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let ts = f.string(from: Date())
        let hr = (vitals?.hr).map(String.init) ?? ""
        let sys = (vitals?.bp?.systolic).map(String.init) ?? ""
        let dia = (vitals?.bp?.diastolic).map(String.init) ?? ""
        let spo2 = (vitals?.spo2).map(String.init) ?? ""
        let rr = (vitals?.rr).map(String.init) ?? ""
        rows.append("\(ts),\(hr),\(sys),\(dia),\(spo2),\(rr)")
        let csv = rows.joined(separator: "\n").appending("\n")

        do {
            try csv.data(using: .utf8)?.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    /// Build a plain-text transcript file (one line per `TranscriptLine`).
    static func writeTranscript(transcript: [TranscriptLine], casualtyId: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let stamp = Self.timestampString()
        let url = dir.appendingPathComponent("transcript-\(casualtyId)-\(stamp).txt")

        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let lines = transcript.map { line -> String in
            let speaker = line.speaker.rawValue.uppercased()
            let ts = f.string(from: line.timestamp)
            return "[\(ts)] \(speaker): \(line.text)"
        }
        let body = lines.joined(separator: "\n").appending("\n")

        do {
            try body.data(using: .utf8)?.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    /// File-size for display, in KB ceiling-rounded. Returns 0 if file missing.
    static func sizeKB(of url: URL?) -> Int {
        guard let url else { return 0 }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return max(1, Int(ceil(size.doubleValue / 1024.0)))
    }

    private static func timestampString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
