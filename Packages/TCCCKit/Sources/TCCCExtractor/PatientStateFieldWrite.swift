// PatientStateFieldWrite.swift
import Foundation

/// The ONLY vocabulary by which a non-extraction caller may write a `PatientState`
/// field. Typed cases, never free-form strings: an LLM-originated string can reach
/// a setter only by being translated into one of these cases by the rubric-bounded
/// `FieldRouter`. The engine applies these and remains the sole writer of state.
public enum PatientStateFieldWrite: Sendable, Equatable {
    // Vitals (TCCC DD-1380 §C)
    case heartRate(Int)
    case spo2(Int)
    case respiratoryRate(Int)
    case bloodPressure(systolic: Int, diastolic: Int, palpated: Bool)
    // MARCH
    case hemorrhageLocation(String)
    case hemorrhageIntervention(String)
    case airwayIntervention(String)
    case consciousness(String)            // AVPU
    case hypothermiaPrevention(String)
    // PAWS
    case pain(String)
    case antibiotics(String)
}
