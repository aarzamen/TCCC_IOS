// TCCC_IOS/Intelligence/OperatorAcceptedFact.swift
import Foundation

/// A candidate fact the operator has accepted. Constructible ONLY from a fact that
/// is a member of a `GraniteValidationResult.acceptedFacts` set — there is no other
/// initializer. This is the type-level half of the LLM-never-mutates invariant:
/// raw model text cannot be turned into one of these, only a schema-validated,
/// operator-accepted fact can.
struct OperatorAcceptedFact: Equatable {
    let fact: GraniteCandidateFact

    init?(_ fact: GraniteCandidateFact, from validation: GraniteValidationResult) {
        guard validation.acceptedFacts.contains(fact) else { return nil }
        self.fact = fact
    }
}
