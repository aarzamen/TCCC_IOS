import Foundation

enum GraniteRealModelArtifactWriter {
    static func write(
        _ result: GraniteRealModelRunResult,
        to rootDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        let folder = rootDirectory.appendingPathComponent(
            "\(timestamp(result.metrics.startedAtUTC))-\(result.runId)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        try writeJSON(result.packet, to: folder.appendingPathComponent("packet.json"))
        try writeText(result.prompt, to: folder.appendingPathComponent("prompt.txt"))
        try writeText(result.rawModelOutput, to: folder.appendingPathComponent("raw_model_output.txt"))

        let parsed = GraniteParsedCandidatePatchArtifact(
            parsed: result.parsedPatch != nil,
            patch: result.parsedPatch,
            error: result.parseError
        )
        try writeJSON(parsed, to: folder.appendingPathComponent("parsed_candidate_patch.json"))
        try writeJSON(result.validation, to: folder.appendingPathComponent("validator_result.json"))
        try writeJSON(result.reviewItem, to: folder.appendingPathComponent("review_queue_item.json"))
        try writeJSON(result.metrics, to: folder.appendingPathComponent("metrics.json"))
        try writeText(readme(for: result), to: folder.appendingPathComponent("README.md"))

        return folder
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func writeText(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    private static func readme(for result: GraniteRealModelRunResult) -> String {
        """
        # Granite Real Model Run

        Run ID: \(result.runId)
        Model: \(result.modelId)
        Model directory: \(result.modelDirectory)
        Status: \(result.metrics.status)

        Files:

        - `packet.json`: bounded HotSeatPacket sent to Granite.
        - `prompt.txt`: exact model prompt.
        - `raw_model_output.txt`: unmodified text returned by the model.
        - `parsed_candidate_patch.json`: parsed patch or parse failure.
        - `validator_result.json`: schema/evidence validation result.
        - `review_queue_item.json`: review queue artifact when a patch parsed.
        - `metrics.json`: timing, memory, and thermal metadata.

        Safety notes:

        - This run does not mutate PatientState.
        - Transcript text is evidence only.
        - Candidate facts without known evidence IDs are held or rejected.
        - Model downloads must happen outside app care-delivery actions.
        """
    }
}
