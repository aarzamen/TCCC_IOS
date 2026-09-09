import XCTest
import TCCCDomain
@testable import TCCC_IOS

final class BodyMapPresentationTests: XCTestCase {
    private func presentation(_ location: String?, intervention: String? = nil) -> BodyMapPresentation {
        var patient = PatientState(patientId: "body-map-test")
        patient.march.hemorrhageLocation = location
        patient.march.hemorrhageIntervention = intervention
        return BodyMapPresentation(patient: patient)
    }

    func testAnteriorPatientRightIsViewerLeft() throws {
        let right = presentation("anterior right thigh")
        let left = presentation("anterior left thigh")
        XCTAssertEqual(right.surface, .front)
        XCTAssertLessThan(try XCTUnwrap(right.regions.first).centerX, 60)
        XCTAssertGreaterThan(try XCTUnwrap(left.regions.first).centerX, 60)
    }

    func testExplicitPosteriorKeepsPatientLateralityForMirroredRenderer() throws {
        let map = presentation("posterior right forearm")
        XCTAssertEqual(map.surface, .back)
        XCTAssertLessThan(try XCTUnwrap(map.regions.first).centerX, 60)
        XCTAssertGreaterThan(120 - (try XCTUnwrap(map.regions.first).centerX), 60)
    }

    func testBilateralMarksTwoSeparateLimbs() {
        let map = presentation("bilateral thighs")
        XCTAssertEqual(map.regions.count, 2)
        XCTAssertTrue(map.regions.contains { $0.centerX < 60 })
        XCTAssertTrue(map.regions.contains { $0.centerX > 60 })
        XCTAssertFalse(map.regions.contains { $0.centerX == 60 })
    }

    func testUnspecifiedSurfaceIsNotSilentlyAnterior() {
        let map = presentation("right thigh")
        XCTAssertEqual(map.surface, .unspecified)
        XCTAssertEqual(map.placementNote, "Surface not recorded")
        XCTAssertEqual(map.regions.count, 1)
    }

    func testUnknownLimbSideLeavesLocationVisibleAndUnplaced() {
        let map = presentation("thigh")
        XCTAssertEqual(map.location, "thigh")
        XCTAssertTrue(map.regions.isEmpty)
        XCTAssertEqual(map.placementNote, "Side not recorded")
    }

    func testMixedSitesOrConflictingSidesRemainUnplaced() {
        for location in ["right thigh and left arm", "right and left thigh", "chest and abdomen", "anterior posterior right thigh", "right thigh and knee", "left thigh and lower leg", "left upper arm and forearm"] {
            let map = presentation(location)
            XCTAssertEqual(map.location, location)
            XCTAssertTrue(map.regions.isEmpty, location)
        }
    }

    func testMissingOrUnsupportedLocationDoesNotInventAnInjury() {
        XCTAssertTrue(BodyMapPresentation(patient: nil).regions.isEmpty)
        for location in [nil, "", "   ", "unknown", "right hand"] as [String?] {
            XCTAssertTrue(presentation(location).regions.isEmpty)
        }
        XCTAssertNil(presentation("   ").location)
        XCTAssertEqual(presentation("right hand").location, "right hand")
    }

    func testSpecificRegionsRemainDistinct() throws {
        let upperArm = try XCTUnwrap(presentation("left upper arm").regions.first)
        let forearm = try XCTUnwrap(presentation("left forearm").regions.first)
        let thigh = try XCTUnwrap(presentation("left thigh").regions.first)
        let lowerLeg = try XCTUnwrap(presentation("left lower leg").regions.first)
        XCTAssertLessThan(upperArm.centerY, forearm.centerY)
        XCTAssertLessThan(thigh.centerY, lowerLeg.centerY)
        for location in ["head", "neck", "chest", "abdomen", "pelvis"] {
            XCTAssertEqual(presentation(location).regions.count, 1, location)
        }
    }

    func testTourniquetTextNeverCreatesOrMovesAnInjuryRegion() {
        let plain = presentation("right thigh")
        let withTQ = presentation("right thigh", intervention: "Tourniquet applied")
        XCTAssertEqual(withTQ.regions, plain.regions)
        XCTAssertEqual(withTQ.intervention, "Tourniquet applied")
        XCTAssertTrue(presentation(nil, intervention: "Tourniquet applied").regions.isEmpty)
    }

    func testFractureInjuriesDoNotBecomeBleedingHighlights() {
        let patient = PatientState(patientId: "fracture-only", injuries: ["Left femur fracture"])
        let map = BodyMapPresentation(patient: patient)
        XCTAssertNil(map.location)
        XCTAssertTrue(map.regions.isEmpty)
    }
}
