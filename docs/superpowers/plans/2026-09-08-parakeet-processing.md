# Parakeet streaming processing repair

**Goal:** Process all admitted audio in order and deliver honest capture completion.
**Authority:** PROJECT_POLICY.md; Codex leads, Codex implements and verifies the repair with scoped workers and independent integration review. Native Claude authored the unsuccessful vocabulary experiment; its later repair attempt produced no patch and was stopped.
**Architecture:** One serial decoder consumer, bounded audio admission, drain before finish/reset, request-scoped completion and cumulative transcript handling. Preserve local inference, protected audio files and operator decision authority.

## Source evidence

In FluidAudio 0.14.4, `appendAudio` only buffers. `finish` processes one prefix chunk and clears the queue. The production adapter called only `appendAudio`; with `.ms160`, teardown could decode only 160 milliseconds. The library's EOU callback contains cumulative tokens and does not reset state. Concurrent `process` calls are unsafe because inference suspends inside the actor.

## Delivery

- [x] Serialized processor, adapter wiring, focused regression tests for order, non-overlap, drain, failure and cumulative text.
- [x] Request-scoped consumer integration, test/build review and on-device evidence.
- [ ] Review, publish supported source changes and install the resulting normal app.

## Field experiment findings

Private excerpts and draft Plaud transcripts remain outside the repository. Plaud is comparison evidence, not audited ground truth. The draft references contain four occurrences of the target term across three passages. Apple on-device, vocabulary-biased Apple, DSP-preprocessed Apple, cached local Whisper base.en and an iPhone cached-Parakeet file probe recovered none of those canonical terms. This does not establish audited field recall; audio alignment and human transcription remain outstanding.

The serial Parakeet file probe consumed every input frame in five field excerpts and one matched synthetic control. It recovered more text than Apple in several excerpts, without resolving target-term recognition. The probe directly calls the decoder and is not evidence that live microphone wiring works. Vocabulary biasing and the temporary diagnostic trace are not included in the production change because the experiment did not demonstrate improved target-term coverage.

Same-device matched synthetic control (134.381 seconds): the old append-only sequence yields zero words; sequential decoding yields 315 raw whitespace-delimited words. This demonstrates the adapter API defect independently of model selection. Raw word count is not an accuracy score.

## Verification and limits

- App suite: 178 tests executed, three documented skips, zero failures. Eight new processor/integration tests cover all admitted buffers, serialized suspended inference, finish/reset boundaries, duplicate close, repeated identical utterances, decode failure, overload, ingress failure and operator decisions made while old audio is queued.
- Mutation check: bypassing `decoder.process` makes the coverage regression fail on four assertions; restoring inference passes the full suite.
- Independent review found two adapter faults, now corrected: shutdown drains the microphone ingress FIFO before the decoder FIFO, and acquisition timestamps survive queueing and pre-roll rather than being assigned after a delay.
- Signed iPhone build succeeds. The temporary on-device probe uses the production `FluidParakeetDecoder` and `ParakeetAudioProcessor`, with an enlarged queue solely to admit whole files rapidly. All 8,517,991 admitted 16 kHz samples are processed across six files. The 225-second excerpt accounts for 3,600,000 samples. The matched synthetic control yields 315 words. Segment IDs are unique, and no run reports failure.
- The field file that produces two EOU segments yields 83 words with production segment reset, versus 94 in the direct cumulative decoder probe. Neither recovers the draft reference's canonical target term; word counts alone do not establish which output is more accurate.
- Production retains its 90-second decoder-queue limit and bounded microphone queue. Failures remain visible, and raw recording continues until stop when decoding alone fails. Apple Speech remains the default backend.
- Live microphone acoustics, interruption behavior on physical hardware and boundary-word accuracy remain to be exercised. The file probe bypasses AVAudioEngine ingress and is not evidence for those paths. Raw recordings, Plaud draft text, hypothesis logs and diagnostic code are not committed.
