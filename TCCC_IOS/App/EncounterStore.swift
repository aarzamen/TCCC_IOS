// TCCC_IOS/App/EncounterStore.swift
import Foundation
import TCCCExtractor

/// On-disk index of all encounters. Source of truth is each casualty's
/// events.jsonl; this manifest is a rebuildable pointer to the active one.
struct EncounterManifest: Codable, Sendable {
    var schemaVersion: Int = 1
    var activeCasualtyId: String?
    var encounters: [Entry] = []

    struct Entry: Codable, Sendable {
        let casualtyId: String
        let dirName: String
        let startUnix: Double
        var endedUnix: Double?
        var archivedUnix: Double?
        var status: String          // "active" | "archived"
    }
}

/// App-layer owner of all encounter persistence. Serial actor ⇒ ordered,
/// off-MainActor disk writes. TCCCKit never touches disk.
actor EncounterStore {
    private let baseURL: URL
    private var activeDir: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        self.encoder = e; self.decoder = d
    }

    private var encountersDir: URL { baseURL.appendingPathComponent("encounters", isDirectory: true) }
    private var manifestURL: URL { encountersDir.appendingPathComponent("manifest.json") }

    func startNewCasualty(id: String, startUnix: Double) throws {
        try ensureEncountersDir()
        // Collision-proof: the integer-second stamp alone is NOT unique — End Care reuses
        // the same casualtyId with startUnix=now, and createDirectory(withIntermediateDirectories:)
        // does not throw on an existing dir. A same-second rotation would otherwise reuse the
        // just-archived dir and resurrect its PHI as "active" on next launch. The UUID suffix
        // removes the wall-clock-second uniqueness dependency entirely.
        let dirName = "\(id)_\(Int(startUnix))_\(UUID().uuidString.prefix(8))"
        let dir = encountersDir.appendingPathComponent(dirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        activeDir = dir
        var m = (try? loadManifest()) ?? EncounterManifest()
        m.encounters.append(.init(casualtyId: id, dirName: dirName, startUnix: startUnix,
            endedUnix: nil, archivedUnix: nil, status: "active"))
        m.activeCasualtyId = id
        try saveManifest(m)
    }

    func appendToActive(_ events: [EncounterEvent]) throws {
        guard let dir = activeDir else { return }
        let file = dir.appendingPathComponent("events.jsonl")
        for event in events {
            let line = String(decoding: try encoder.encode(event), as: UTF8.self)
            try ProtectedWrite.appendLine(line, to: file)
        }
    }

    func archiveActive(endedUnix: Double) throws {
        guard var m = try? loadManifest(), let activeId = m.activeCasualtyId else { return }
        if let i = m.encounters.firstIndex(where: { $0.casualtyId == activeId && $0.status == "active" }) {
            m.encounters[i].archivedUnix = endedUnix
            m.encounters[i].status = "archived"
        }
        m.activeCasualtyId = nil
        try saveManifest(m)
        activeDir = nil
    }

    func purgeAll() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: encountersDir.path) {
            try fm.removeItem(at: encountersDir)
        }
        activeDir = nil
    }

    func loadActiveEncounter() throws -> (casualtyId: String, log: EncounterLog)? {
        guard let m = try? loadManifest(), let activeId = m.activeCasualtyId,
              let entry = m.encounters.first(where: { $0.casualtyId == activeId && $0.status == "active" })
        else { return nil }
        let dir = encountersDir.appendingPathComponent(entry.dirName, isDirectory: true)
        activeDir = dir
        return (activeId, loadLog(from: dir.appendingPathComponent("events.jsonl")))
    }

    /// Persist the §C vital-sign grid for the active encounter (protected).
    /// Separate from the event log: `vitalsLog` is an app-layer rolling buffer,
    /// not part of `PatientState`, so it lives beside `events.jsonl` rather than
    /// in it. No-op when there is no active encounter.
    func saveSectionC(_ data: Data) throws {
        guard let dir = activeDir else { return }
        try ProtectedWrite.data(data, to: dir.appendingPathComponent("sectionC.json"))
    }

    /// Load the persisted §C grid for the active encounter, or nil if none.
    func loadSectionC() -> Data? {
        guard let dir = activeDir else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent("sectionC.json"))
    }

    // MARK: - Helpers

    private func ensureEncountersDir() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: encountersDir.path) {
            try fm.createDirectory(at: encountersDir, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
        }
    }

    private func loadManifest() throws -> EncounterManifest {
        let data = try Data(contentsOf: manifestURL)
        return try decoder.decode(EncounterManifest.self, from: data)
    }

    private func saveManifest(_ m: EncounterManifest) throws {
        try ProtectedWrite.data(try encoder.encode(m), to: manifestURL)
    }

    /// Decode a JSONL log, tolerating a truncated final line (crash mid-write):
    /// any line that fails to decode is skipped.
    private func loadLog(from url: URL) -> EncounterLog {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return EncounterLog() }
        var log = EncounterLog()
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            if let event = try? decoder.decode(EncounterEvent.self, from: Data(line.utf8)) {
                log.append(event)
            }
        }
        return log
    }
}
