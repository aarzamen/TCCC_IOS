import Foundation

/// Keyword-biased ASR prompt for Granite Speech 4.0 1B (Sprint 1 v3
/// §G2 task 5).
///
/// Granite Speech doesn't expose a separate "biasing list" parameter —
/// the keyword set is appended to the prompt text and the LLM decoder
/// learns to favor those tokens at decode time. This list is the TCCC
/// vocabulary that the ASR otherwise fumbles into homophones (e.g.
/// "TXA" → "tax-A", "MEDEVAC" → "medi-vac").
///
/// Sourced from the v1 sprint spec §6 acceptance baseline tokens plus
/// the medications + interventions enumerated in `GraniteCandidatePatch`
/// (TCCC_IOS/Intelligence/GraniteCandidatePatch*).
public enum GraniteSpeechPrompt {
    /// Default ASR prompt. Use for ordinary transcription.
    public static let asr: String = """
    <|audio|>can you transcribe the speech into a written format?
    Keywords: tourniquet, TXA, GSW, ZMIST, DD1380, AVPU, SpO2, MEDEVAC, 9-line, MARCH, hemorrhage, pneumothorax, ketamine, fentanyl, morphine, moxifloxacin, ertapenem, cefazolin, Hextend, lactated ringer's, whole blood, plasma, needle decompression, chest seal, NPA, cric, Reaper, Dawson, NKDA.
    """

    /// Prompt for AST (speech translation). Sprint 1 doesn't surface
    /// translation in UI, but kept here so the model's full surface is
    /// reachable if a future phase wants it (Granite Speech supports
    /// EN/FR/DE/ES/PT/JA per the per-model README).
    public static func translate(toLanguage code: String) -> String {
        "<|audio|>Translate the speech to \(code)."
    }
}
