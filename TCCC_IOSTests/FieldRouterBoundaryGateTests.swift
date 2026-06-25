// TCCC_IOSTests/FieldRouterBoundaryGateTests.swift
import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

final class FieldRouterBoundaryGateTests: XCTestCase {
    // --- Rejections: bad facts stay OUT (each explicit, never coerced) ---
    func testUnknownDomainRejected() {
        XCTAssertEqual(FieldRouter.route(domain: "bogus", field: "heartRate", value: "88"),
                       .rejected(.unknownDomain("bogus")))
    }
    func testKnownDomainUnknownFieldRejected() {
        XCTAssertEqual(FieldRouter.route(domain: "vitals", field: "notAField", value: "88"),
                       .rejected(.unknownField("notAField")))
    }
    func testValueOutOfRubricRangeRejected() {
        XCTAssertEqual(FieldRouter.route(domain: "vitals", field: "heartRate", value: "999"),
                       .rejected(.valueOutOfRubricRange(field: "heartRate", value: "999")))
    }
    func testKnownFieldNoSetterWiredRejected() {
        // "pulse" is in GraniteSchemaValidator.allowedFields but has no wired setter.
        XCTAssertEqual(FieldRouter.route(domain: "vitals", field: "pulse", value: "110"),
                       .rejected(.noSetterWired(domain: "vitals", field: "pulse")))
    }
    // --- Acceptance: a good fact goes THROUGH (the 5th, positive member) ---
    func testWellFormedWiredInRangeRoutesToMutation() {
        XCTAssertEqual(FieldRouter.route(domain: "vitals", field: "heartRate", value: "88"),
                       .mutation(.heartRate(88)))
    }
    // A reject-everything router must FAIL this suite — the positive case guards that.
}
