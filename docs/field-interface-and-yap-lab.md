# Field interface and Yap Lab

The launcher has three independent workspaces. TCCC documents casualties;
Yap Lab preserves audio/transcription experiments separately; DevTools plays
synthetic scenarios and runs Granite diagnostics. Return through Settings →
Return to launcher when capture is idle. Microphone teardown completes before
entering another workspace.

## Clinical corrections

- Capture → Vitals opens measured-value entry. Blank fields keep prior clinical
  values. A manual reading stores only the observations entered at that time;
  repeating the same measurement creates a separate reading. Section C displays
  the most recent four retained readings, and CSV exports those recorded times,
  AVPU and pain values. It is not a complete lifetime vital-sign history.
- Capture → Med given and Actions → TQ apply record actual interventions after
  input. TQ entry does not imply successful hemorrhage control. Actions → Mark
  time saves a timestamped operator note. These actions previously only wrote
  transient placeholder messages.
- Card → Casualty details edits identity/allergies; unknowns stay blank. Card →
  Assessment corrects mechanism, injuries and precedence through audited engine
  writes. Other MARCH fields remain driven by capture/review.
- MEDEVAC → Add/Edit or Edit fields opens the operational worksheet. Equipment,
  transport type, security, marking, nationality and CBRN have no default values.
  Unknown/unverified values do not count as complete. GPS supplies Line 1.
- Radio drafts preserve the exact worksheet or fall back visibly to its exact
  deterministic text. A changed encounter, field or transcript clears stale
  wording. Call made records an operator-confirmed radio call; the app does not
  transmit a request. Displaying or sharing QR never records a completed call.
- Handoff distinguishes an exportable draft from complete documentation and
  surfaces export failures on the screen. QR is plain structured data; at-rest
  file protection is not an encrypted transport claim.

Identity, operational fields and notes live in a protected per-encounter file
beside the clinical event log. They survive relaunch and archive with the
encounter; they do not carry into the next casualty.

## Yap Lab

1. Record, or import an audio file from Files. Choose speech recognition
   independently from the language model. Apple/Granite support file input;
   Parakeet currently supports live capture in this interface. Import or
   Re-transcribe while Parakeet is selected asks you to choose Apple or Granite;
   the recognizer changes only after your explicit choice.
2. Each raw result retains its source audio. Re-transcribe compares that selected
   source with another supported recognizer. Play the selected source to listen
   for missed or changed words. Playback stops before capture or generation.
3. Choose a prompt preset, then edit its system and task instructions. Generate
   a separate draft. The raw transcript is never rewritten by the LLM.
4. Search raw text and drafts; inspect word counts, elapsed generation time
   (including loading), exact prompts and source-linked history. Timing is a
   local run observation, not a standardized benchmark.
5. Save/reopen sessions or share their text. Sessions and recordings remain in
   protected `Documents/YapLab`, separate from clinical records. Cancel retains
   incomplete recognition evidence and waits for active work to release resources.
   Recognition failure details stay with the raw row after reopening and are
   included when sharing. An unreadable session produces a warning without
   hiding healthy sessions or removing the original file.

If a permission is denied, the controls explain which access is missing and
offer Open Settings. Permission state refreshes on return. System permission
dialogs can finish without cancelling the pending operation; moving the app
to the background still cancels lab work and saves retained evidence. Simulator
Settings may open at its root; physical permission recovery requires a device
check.

Presets include punctuation cleanup, summaries, explicit action lists, fidelity
review, verbatim checking and meeting notes. They do not infer missing facts.
Speech errors remain possible; LLM fluency is not evidence of transcription
accuracy. Lab text never runs the clinical extractor or changes casualty state.

## Useful DevTools

Sender renders scripts using packaged Kokoro or clearly labeled Device Speech
fallback. The ambient meter is opt-in. The pitch control applies to Device
Speech; unsupported Kokoro voices use the labeled fallback. Receiver's empty
launcher card is removed. Granite Bake-off and Live accept validated local
assets and show setup errors; authoritative results drive Bake-off metrics.

## Offline preparation and model pairing

See [offline installation and pairing evidence](research/2026-09-09-offline-model-installation.md).
The signed field build embeds all six non-Apple packages (three text LLMs,
two ASR models and Kokoro TTS with auxiliary assets), about 5.75 GB. Source
control contains the staging/build tools and manifests schema, not model weights.
Release builds require the pack explicitly so a new install cannot silently omit
it. Apple Speech, Apple Intelligence and Device Speech voice assets are managed
by iOS and cannot be included by this build script.

Parakeet 160ms + LFM2 1.2B is a useful first packaged comparison. It is not a
proven winner over the current Apple defaults. Compare the same audio and prompt
on the same phone, retaining raw text, elapsed time and failure evidence.

The interactive [system explorer](../reference/system-explorer/tccc-switchboard.html)
is a synthetic teaching simulation, not a performance benchmark. Its evidence
map identifies the actual source behind each system boundary.
