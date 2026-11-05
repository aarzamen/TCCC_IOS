# Driving notes — 2026-05-05

Two tasks to address before the field trial with the Corpsman at TCCC. Both
about transcription quality, not features.

## 1. Chunk-boundary truncation bug (CRITICAL — blocks field use)

### Symptom
- Bench test: phone held up to a YouTube video, speaker clear and loud.
- During each chunk window: registers every word, transcribes perfectly.
- **At the chunk boundary:** the recognizer appears to absorb a long burst of
  fast-spoken words (≈1 minute of content) and then collapses the entire
  burst down to two words.

### Why this matters
- A Corpsman running with the phone in a chest pocket will speak in bursts
  separated by breathing/footfall. The current behavior is the inverse of
  what we need: it captures clean lab speech but discards real running
  speech precisely at the moments that contain the intervention narration.
- Ground truth for the field trial: phones in chest pockets during runs at
  TCCC. We need basic transcription with reasonable accuracy at running pace
  before that's useful.

### Likely scope
We previously over-corrected toward not registering long, irregular gaps —
and the result is the opposite failure: the chunker now claims the whole
trailing burst, then the recognizer truncates it. Look at:
- The chunk-boundary handoff in the SpeechRecognizer / coordinator
- How partial vs. final results are committed at the boundary
- Whether the running window flushes cleanly before the next chunk starts
- Whether VAD silence-thresholds were tightened in the gap fix and now
  starve the recognizer

The user's instinct: "we have worked ourselves into a corner where the app
may not work well for anyone moving along at a reasonable clip."

### Acceptance bar
Not perfection. **Basic transcription with reasonable accuracy** for a
Corpsman talking at running pace into a chest-pocket phone. The bar the
user described, verbatim.

## 2. UI flourish removal — make it serious, straight, lean

Strip Hollywood-soldier-tech-warrior styling. Keep functional indicators only.
The user called it "cringe" — anything that isn't grounded in TCCC workflow
should go.

What stays (examples the user gave as acceptable):
- Plain Wi-Fi-with-X / Bluetooth-with-X status indicators
- Anything that maps directly to a TCCC field need

What goes:
- Tactical-themed flourishes, dramatic typography, ornamentation
- Anything that exists to look cool rather than to communicate state

Default to: TCCC operators are busy, tired, sometimes injured. The UI's
job is to be readable and unambiguous, not to perform a vibe.

## Out of scope tonight

- Don't refactor architecture. Fix the bug, trim the UI, that's it.
- Don't add features.
- ChoiceVoice (the TTS boombox) is unrelated and already shipped to GitHub.
