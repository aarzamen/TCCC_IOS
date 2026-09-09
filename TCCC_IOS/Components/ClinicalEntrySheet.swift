import SwiftUI
import TCCCDomain
import TCCCExtractor

struct ClinicalEntrySheet: View {
    let state: AppState
    let kind: ClinicalEntryKind
    @Environment(\.dismiss) private var dismiss
    @State private var metadata = EncounterOperatorMetadata()
    @State private var vitals = ManualVitalsDraft()
    @State private var mechanism = ""
    @State private var classification = ""
    @State private var injuries = ""
    @State private var details = ""
    @State private var location = ""
    @State private var time = Date()
    @State private var encounter = UUID()
    @State private var busy = false
    @State private var applied = false
    @State private var manualReading: AppState.SectionCReading?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(state.casualtyId) · Operator entry").font(.headline)
                    Text(help).font(.subheadline).foregroundStyle(.secondary)
                }
                fields
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("clinical-entry-error") } }
            }
            .navigationTitle(kind.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(busy).accessibilityIdentifier("clinical-entry-save")
                }
            }
            .interactiveDismissDisabled(busy || applied)
            .onAppear {
                encounter = state.encounterIdentity
                metadata = state.operatorMetadata
                mechanism = state.primaryPatient?.mechanismOfInjury ?? ""
                classification = state.primaryPatient?.classification?.rawValue ?? ""
                injuries = state.primaryPatient?.injuries.joined(separator: "\n") ?? ""
            }
        }
    }

    private var help: String {
        switch kind {
        case .vitals: "Add a reading. Blank fields keep existing observations unchanged."
        case .identity: "Unknown details stay blank. Enter allergies only when known."
        case .assessment: "Corrections update the clinical record and remain in its audit history. One injury per line."
        case .nineLine: "Enter known operational values. Empty lines remain unverified. Line 1 comes from the GPS control on the 9-line screen."
        case .tourniquet: "Record what was performed. Saving does not imply bleeding is controlled."
        case .medication: "Document the medication, dose and route actually given; no dose is supplied automatically."
        case .mark: "A timestamped operator note is saved with this encounter."
        }
    }

    @ViewBuilder private var fields: some View {
        switch kind {
        case .identity:
            Section("Identity") {
                TextField("Name", text: $metadata.name)
                TextField("Unit", text: $metadata.unit)
                TextField("Service number (masked if preferred)", text: $metadata.serviceNumber)
                TextField("Allergies — blank means unknown", text: $metadata.allergies)
            }
        case .vitals:
            Section("Measured now") {
                TextField("Pulse / min", text: $vitals.hr).keyboardType(.numberPad)
                HStack {
                    TextField("Systolic", text: $vitals.systolic).keyboardType(.numberPad)
                    Text("/")
                    TextField("Diastolic", text: $vitals.diastolic).keyboardType(.numberPad)
                }
                TextField("SpO₂ %", text: $vitals.spo2).keyboardType(.numberPad)
                TextField("Respirations / min", text: $vitals.rr).keyboardType(.numberPad)
                Picker("AVPU", selection: $vitals.avpu) {
                    Text("Not entered").tag("")
                    ForEach(ConsciousnessLevel.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                TextField("Pain 0–10", text: $vitals.pain).keyboardType(.numberPad)
            }
        case .assessment:
            Section("Assessment") {
                TextField("Mechanism of injury", text: $mechanism)
                Picker("Precedence", selection: $classification) {
                    Text("Unknown").tag("")
                    ForEach(Classification.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                TextEditor(text: $injuries).frame(minHeight: 100).accessibilityLabel("Injuries, one per line")
            }
        case .tourniquet, .medication:
            Section("Performed intervention") {
                DatePicker("Time performed", selection: $time, displayedComponents: [.date, .hourAndMinute])
                if kind == .tourniquet { TextField("Location and side", text: $location) }
                TextField(kind == .medication ? "Medication, dose, route" : "Type / details (optional)", text: $details, axis: .vertical)
            }
        case .mark:
            Section("Note") { TextField("Optional note", text: $details, axis: .vertical) }
        case .nineLine:
            Section("Operational lines") {
                ForEach(NineLineForm.derive(from: [], locationFix: state.locationFix).entries.filter { $0.number != 1 }) { entry in
                    TextField("\(entry.number) · \(entry.label)", text: Binding(
                        get: { metadata.nineLineValues[entry.number] ?? "" },
                        set: { metadata.nineLineValues[entry.number] = $0 }))
                        .textInputAutocapitalization(.characters)
                }
            }
        }
    }

    private func save() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            guard encounter == state.encounterIdentity else { throw ClinicalEntryError(message: "Encounter changed. Close and reopen the editor.") }
            switch kind {
            case .identity, .nineLine:
                // Merge only the edited group; preserve notes/other fields added meanwhile.
                var current = state.operatorMetadata
                if kind == .identity {
                    current.name = metadata.name; current.unit = metadata.unit
                    current.serviceNumber = metadata.serviceNumber; current.allergies = metadata.allergies
                } else { current.nineLineValues = metadata.nineLineValues }
                try await state.saveOperatorMetadata(current, encounter: encounter)
            case .mark:
                try await state.saveOperatorNote(text: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "MARK" : "MARK · " + details)
            default:
                if !applied {
                    let writes: [PatientStateFieldWrite]
                    switch kind {
                    case .vitals:
                        writes = try vitals.writes()
                        manualReading = try vitals.reading()
                    case .assessment:
                        writes = [.mechanismOfInjury(mechanism.isEmpty ? nil : mechanism),
                            .classification(Classification(rawValue: classification)),
                            .setInjuries(injuries.split(separator: "\n").map(String.init))]
                    case .tourniquet:
                        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClinicalEntryError(message: "Enter the tourniquet location and side.") }
                        writes = [.hemorrhageIntervention("Tourniquet"), .hemorrhageLocation(location),
                            .appendIntervention(.init(timestamp: time, kind: .tourniquet, description: "Tourniquet · \(location)" + (details.isEmpty ? "" : " · \(details)")))]
                    case .medication:
                        guard !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClinicalEntryError(message: "Enter the medication, dose and route actually given.") }
                        writes = [.appendIntervention(.init(timestamp: time, kind: .medication, description: details))]
                    default: writes = []
                    }
                    try await state.applyClinicalEntry(writes, encounter: encounter, recordsVitals: kind == .vitals)
                    applied = true
                }
                try await state.verifyClinicalEntrySaved(encounter: encounter)
                if let manualReading { try await state.saveManualReading(manualReading, encounter: encounter) }
            }
            Haptics.notify(.success)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
