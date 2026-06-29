import XCTest
import TCCCDomain
@testable import TCCCReports

final class DD1380MapperTests: XCTestCase {

    // Fixed timestamps → deterministic date/time output.
    private let encounterStart = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
    private let now = Date(timeIntervalSince1970: 1_700_003_600)

    private func input(
        patient: PatientState,
        name: String = "DOE, J.",
        last4: String = "4471",
        service: String = "",
        unit: String = "2/75 RGR",
        allergies: String = "NKDA",
        operatorName: String = "HAWK-06",
        readings: [DD1380SectionCReading] = []
    ) -> DD1380MapperInput {
        DD1380MapperInput(
            patient: patient, casualtyId: "C-04", casualtyName: name, casualtyLast4: last4,
            casualtySex: nil, casualtyService: service, casualtyUnit: unit, casualtyAllergies: allergies,
            operatorName: operatorName, operatorLast4: "", sectionCReadings: readings,
            encounterStart: encounterStart, now: now
        )
    }

    // 1. Empty/minimal state maps without crashing and leaves unknowns blank.
    func testEmptyStateMapsWithoutCrashingAndLeavesUnknownsBlank() {
        let p = PatientState(patientId: "PATIENT_1")
        let card = DD1380Mapper.map(input(patient: p, name: "", last4: "", unit: "", allergies: ""))

        XCTAssertEqual(card.nameLastFirst, "")
        XCTAssertEqual(card.last4, "")
        XCTAssertEqual(card.battleRosterNumber, "")   // no name/last4 → blank, not invented
        XCTAssertNil(card.evacCategory)               // nil classification → blank
        XCTAssertNil(card.sex)                         // no source → blank
        XCTAssertEqual(card.service, "")
        XCTAssertFalse(card.mechanisms.anyChecked)
        XCTAssertTrue(card.tourniquets.isEmpty)
        XCTAssertTrue(card.medications.isEmpty)
        XCTAssertEqual(card.notes, "")
        // Date/time still derive from the encounter start.
        XCTAssertEqual(card.dateDDMMMYY, "14-NOV-23")
        XCTAssertEqual(card.timeHHMM, "2213Z")
    }

    // 2. GSW thigh + tourniquet maps mechanism, injury location, and TQ fields.
    func testGSWThighWithTourniquetMapsMechanismLocationAndTourniquet() {
        let tq = Intervention(timestamp: encounterStart, kind: .tourniquet, description: "CAT applied")
        let p = PatientState(
            patientId: "PATIENT_1",
            mechanismOfInjury: "GSW",
            march: MARCHState(hemorrhageLocation: "right thigh", hemorrhageIntervention: "tourniquet applied"),
            interventions: [tq],
            classification: .urgent
        )
        let card = DD1380Mapper.map(input(patient: p))

        XCTAssertTrue(card.mechanisms.gsw)
        XCTAssertFalse(card.mechanisms.other)
        XCTAssertEqual(card.tourniquets.count, 1)
        XCTAssertEqual(card.tourniquets.first?.limb, .rightLeg)   // "right thigh" → R Leg
        XCTAssertNil(card.tourniquets.first?.type)                // never inferred
        XCTAssertEqual(card.tourniquets.first?.timeHHMM, "2213")
        XCTAssertTrue(card.treatments.tqExtremity)
        XCTAssertTrue(card.notes.contains("Hemorrhage: right thigh"))
    }

    // 3. Classification maps to evacuation category.
    func testClassificationMapsToEvacCategory() {
        func evac(_ c: Classification?) -> DD1380EvacCategory? {
            DD1380Mapper.map(input(patient: PatientState(patientId: "P", classification: c))).evacCategory
        }
        XCTAssertEqual(evac(.urgent), .urgent)
        XCTAssertEqual(evac(.urgentSurgical), .urgent)
        XCTAssertEqual(evac(.priority), .priority)
        XCTAssertEqual(evac(.routine), .routine)
        XCTAssertNil(evac(.expectant))   // no DD1380 box
        XCTAssertNil(evac(nil))
    }

    // 4. Section C readings flow into the grid, capped at four columns.
    func testSectionCReadingsMapIntoColumnsCappedAtFour() {
        let readings = (0..<6).map { i in
            DD1380SectionCReading(timeHHMM: String(format: "08%02d", i), pulse: "\(90 + i)",
                                  bloodPressure: "120/80", respiratoryRate: "18", spo2: "97", avpu: "A")
        }
        let card = DD1380Mapper.map(input(patient: PatientState(patientId: "P"), readings: readings))
        XCTAssertEqual(card.sectionCReadings.count, 4)
        XCTAssertEqual(card.sectionCReadings.first?.pulse, "90")
        XCTAssertEqual(card.sectionCReadings.last?.pulse, "93")
        XCTAssertEqual(card.sectionCReadings.first?.bloodPressure, "120/80")
    }

    // 5. Meds map only when represented in structured interventions.
    func testMedicationsMapOnlyWhenRepresentedInStructuredState() {
        let meds = [
            Intervention(timestamp: encounterStart, kind: .painManagement, description: "Ketamine 50mg IM"),
            Intervention(timestamp: encounterStart, kind: .antibiotic, description: "Moxifloxacin 400mg PO"),
            Intervention(timestamp: encounterStart, kind: .medication, description: "TXA 2g IV"),
        ]
        let withMeds = DD1380Mapper.map(input(patient: PatientState(patientId: "P", interventions: meds)))
        XCTAssertEqual(withMeds.medications.count, 3)
        XCTAssertEqual(withMeds.medications.first { $0.category == .analgesic }?.name, "Ketamine 50mg IM")
        XCTAssertEqual(withMeds.medications.first { $0.category == .antibiotic }?.name, "Moxifloxacin 400mg PO")
        XCTAssertEqual(withMeds.medications.first { $0.category == .other }?.name, "TXA 2g IV")

        // No med interventions → no med rows invented.
        let noMeds = DD1380Mapper.map(input(patient: PatientState(patientId: "P")))
        XCTAssertTrue(noMeds.medications.isEmpty)
    }

    // 6. Unknown medication sub-fields (dose/route) remain blank, not invented.
    func testUnknownMedicationDetailsRemainBlank() {
        let p = PatientState(patientId: "P", interventions: [
            Intervention(timestamp: encounterStart, kind: .medication, description: "Ketamine"),
        ])
        let med = DD1380Mapper.map(input(patient: p)).medications.first
        XCTAssertEqual(med?.name, "Ketamine")
        XCTAssertNil(med?.dose)
        XCTAssertNil(med?.route)
        XCTAssertEqual(med?.timeHHMM, "2213")
    }

    // 7. Notes carry unmapped structured facts (not prose / not invented).
    func testNotesContainUnmappedStructuredFacts() {
        let p = PatientState(
            patientId: "P",
            march: MARCHState(hemorrhageLocation: "left arm", breathSounds: "absent left", skinSigns: "pale"),
            injuries: ["GSW left forearm"],
            paws: PAWSAssessment(wounds: "packed")
        )
        let notes = DD1380Mapper.map(input(patient: p)).notes
        XCTAssertTrue(notes.contains("Hemorrhage: left arm"))
        XCTAssertTrue(notes.contains("Injuries: GSW left forearm"))
        XCTAssertTrue(notes.contains("Breath sounds: absent left"))
        XCTAssertTrue(notes.contains("Skin: pale"))
        XCTAssertTrue(notes.contains("Wounds: packed"))
    }

    // 8. Deterministic: same input → identical DD1380CardData.
    func testDeterministicOutput() {
        let p = PatientState(
            patientId: "P",
            mechanismOfInjury: "GSW",
            march: MARCHState(hemorrhageLocation: "right thigh"),
            interventions: [Intervention(timestamp: encounterStart, kind: .tourniquet, description: "CAT")],
            classification: .urgentSurgical
        )
        let inp = input(patient: p)
        XCTAssertEqual(DD1380Mapper.map(inp), DD1380Mapper.map(inp))
    }

    // Battle Roster derivation: first initial + last initial + last4.
    func testBattleRosterDerivation() {
        XCTAssertEqual(DD1380Mapper.battleRoster(name: "DOE, J.", last4: "4471"), "JD4471")
        XCTAssertEqual(DD1380Mapper.battleRoster(name: "DOE, J.", last4: "•• 4471"), "JD4471")
        XCTAssertEqual(DD1380Mapper.battleRoster(name: "DOE, J.", last4: ""), "")
        XCTAssertEqual(DD1380Mapper.battleRoster(name: "Madonna", last4: "4471"), "") // no comma → blank
    }

    // Generic "blast" has no DD1380 box → Other + verbatim text, not a guess.
    func testUnrecognizedMechanismGoesToOther() {
        let p = PatientState(patientId: "P", mechanismOfInjury: "blast injury")
        let card = DD1380Mapper.map(input(patient: p))
        XCTAssertFalse(card.mechanisms.ied)
        XCTAssertTrue(card.mechanisms.other)
        XCTAssertEqual(card.mechanisms.otherText, "blast injury")
        XCTAssertTrue(card.notes.contains("MOI: blast injury"))
    }
}
