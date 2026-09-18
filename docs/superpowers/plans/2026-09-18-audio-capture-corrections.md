# Audio gain and transcription corrections

Requested on 18 September 2026: automatic microphone gain and a critical review
with fixes and tests for the three highest-impact audio-to-text issues.

Keep the current Apple on-device default, offline model assets, capture evidence,
manual-decision protection and encounter boundaries. Work directly on authorized
`main`; native Claude receives only curated source and synthetic tests in an
isolated directory. Codex owns review, tests and delivery.

1. **Automatic gain:** replace the misleading manual boost control with explicit
   automatic status. Prefer iOS voice-processing AGC; provide bounded adaptive
   software gain if unavailable, immediate peak headroom, and post-processing
   meters shared by Apple, Parakeet and Granite. Test quiet input, silence,
   abrupt loud input, malformed samples and channel layouts.
2. **Actual backend and source identity:** serialize backend replacement and
   defer a requested switch during recording/finalization. Freeze the actual
   backend for that capture's ledger. Test idle and in-flight changes with
   controlled streams, including cancellation and late results.
3. **Apple buffered audio timestamps:** timestamp PCM at capture, carry it
   through pre-roll and queued successor requests, and use the earliest included
   sample for operator-decision protection. Test the real engine's behavior when
   buffered speech predates a manual correction.
4. **Granite capture integrity:** convert hardware PCM to the recording format,
   bound and drain ordered ingress before closing, and report conversion/write/
   overflow failures as structured failure evidence. Never ingest an error as
   spoken text. Test delayed writes, final drain, sample-rate conversion and
   terminal metadata using synthetic PCM and real temporary audio files.

Independent workers own nonoverlapping components; the lead integrates shared
gain processing after those edits. Run focused regressions, full TCCCKit tests,
the simulator build and the signed iPhone build with complete offline assets.
Update the connected phone in place and distinguish these checks from acoustic
accuracy and hardware automatic-gain verification.
