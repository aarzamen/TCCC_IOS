import Foundation
import TCCCDomain

/// Builds a short prose summary of the encounter from a `PatientState`. The
/// medic uses this when verbally handing the iPhone (or its summary) to
/// Role-2 — a 2–3 sentence narrative reads faster than the structured rows
/// for context, while the rows remain on screen as the source of truth.
struct EncounterNarrativeGenerator {

    static let systemInstructions = """
        You write concise battlefield handoff narratives for combat medics.

        Rules:
        - Output 2 to 3 sentences. No more.
        - Lead with mechanism of injury and the most critical finding.
        - Mention current vitals only if they are clinically relevant (e.g.,
          unstable BP, tachycardia, low SpO₂). Skip normal vitals.
        - Mention major interventions in past tense ("tourniquet applied",
          "TXA administered").
        - End with current trajectory: "stable", "decompensating", "ready for
          evacuation".
        - Never invent fields. If the state is empty, say "Casualty contact
          made — assessment pending."
        - No preamble, no labels, no markdown. Output only the narrative.
        """

    let model: TCCCLanguageModel

    init() {
        self.model = TCCCLanguageModel(instructions: Self.systemInstructions)
    }

    func generate(for patient: PatientState?, casualtyId: String) async throws -> String {
        guard let patient else {
            return "No casualty assessment yet for \(casualtyId)."
        }

        let prompt = buildPrompt(for: patient, casualtyId: casualtyId)
        return try await model.generate(prompt: prompt)
    }

    // MARK: - Prompt building

    private func buildPrompt(for patient: PatientState, casualtyId: String) -> String {
        var lines: [String] = []
        lines.append("Casualty: \(casualtyId)")
        if let moi = patient.mechanismOfInjury {
            lines.append("Mechanism of injury: \(moi)")
        }
        if let cls = patient.classification {
            lines.append("Triage classification: \(cls.rawValue)")
        }

        // MARCH summary
        let m = patient.march
        if let loc = m.hemorrhageLocation { lines.append("Hemorrhage location: \(loc)") }
        if let intervention = m.hemorrhageIntervention { lines.append("Hemorrhage control: \(intervention)") }
        if let airway = m.airwayStatus { lines.append("Airway: \(airway)") }
        if let airwayInt = m.airwayIntervention { lines.append("Airway intervention: \(airwayInt)") }
        if let resp = m.respirationStatus { lines.append("Respiration: \(resp)") }
        if let breath = m.breathSounds { lines.append("Breath sounds: \(breath)") }
        if let respInt = m.respirationIntervention { lines.append("Respiration intervention: \(respInt)") }
        if let pulse = m.pulseStatus { lines.append("Pulse: \(pulse)") }
        if let skin = m.skinSigns { lines.append("Skin signs: \(skin)") }
        if let circInt = m.circulationIntervention { lines.append("Circulation intervention: \(circInt)") }
        if let cons = m.consciousness { lines.append("Consciousness: \(cons)") }
        if let pupils = m.pupilResponse { lines.append("Pupils: \(pupils)") }
        if let hypo = m.hypothermiaPrevention { lines.append("Hypothermia: \(hypo)") }

        // Vitals
        let v = patient.vitals
        var vitals: [String] = []
        if let hr = v.hr { vitals.append("HR \(hr)") }
        if let bp = v.bp {
            let suffix = bp.palpated ? " palp" : ""
            vitals.append("BP \(bp.systolic)/\(bp.diastolic)\(suffix)")
        }
        if let spo2 = v.spo2 { vitals.append("SpO2 \(spo2)%") }
        if let rr = v.rr { vitals.append("RR \(rr)") }
        if let gcs = v.gcs { vitals.append("GCS \(gcs)") }
        if !vitals.isEmpty {
            lines.append("Vitals: \(vitals.joined(separator: ", "))")
        }

        // Interventions
        if !patient.interventions.isEmpty {
            let interventionDescs = patient.interventions.map { "\($0.kind.rawValue): \($0.description)" }
            lines.append("Interventions: \(interventionDescs.joined(separator: "; "))")
        }

        // Injuries
        if !patient.injuries.isEmpty {
            lines.append("Injuries: \(patient.injuries.joined(separator: "; "))")
        }

        // PAWS
        let p = patient.paws
        var paws: [String] = []
        if let pain = p.pain { paws.append("Pain: \(pain)") }
        if let abx = p.antibiotics { paws.append("Antibiotics: \(abx)") }
        if let wounds = p.wounds { paws.append("Wounds: \(wounds)") }
        if let splint = p.splinting { paws.append("Splinting: \(splint)") }
        if !paws.isEmpty {
            lines.append("PAWS: \(paws.joined(separator: "; "))")
        }

        return """
            Patient state:

            \(lines.joined(separator: "\n"))

            Generate the handoff narrative now. Output only the prose.
            """
    }
}
