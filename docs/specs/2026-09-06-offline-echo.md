# Offline acoustic echo cancellation

Recording must not change what a person hears. The microphone therefore stays
raw during a meeting. `offline_echo_cancellation` defaults to true and prepares
two temporary, aligned mono PCM files before recognition: an echo-cleaned
microphone and unchanged system audio. The recording archive and `keep_audio`
policy continue to operate on the original tracks.

The processor is LocalVQE v1.4-AEC 203K in echo-only mode. Noise gating, noise
suppression and gain control are disabled. Its adaptive filter receives the
microphone and far-end reference continuously at 16 kHz in 256-sample hops. A
single model context receives every hop from the start of the meeting and stays
warm across bounded I/O windows. LocalVQE's GCC estimates a bulk delay during
early acquisition and freezes it after a confident estimate; the adaptive
filter can follow residual changes only within its modeled range. Amanu does
not promise reacquisition after an arbitrary playback-route or clock-delay
change. Every non-final window contains 937 complete hops (239,872 samples, or
14.992 seconds); zero padding is introduced only once at the true end of the
stream.

The file model emits the preceding hop. Amanu discards its startup output and
feeds one final zero hop to retain the last 16 ms, keeping the result aligned
and equal in duration to the source timeline. A bounded preflight identifies a
reference that is silent for the entire recording; that case avoids loading the
native model and preserves the microphone exactly. If playback occurs anywhere
in the recording, leading silence still advances the model from absolute t=0
while the output selector preserves those microphone samples exactly. This is
required because starting the model at the first nonzero reference would shift
GCC's acquisition clock and could lock a different bulk delay. After reference
activity, the model output remains selected for exactly 16,000 samples of
reference silence so delayed device echo and room decay are not restored.
Sustained silence after that holdoff uses the original microphone again; the
model continues advancing so its state stays warm.

The universal CPU-only native library and model are build assets, not runtime
downloads. `scripts/build-localvqe.sh` checks out LocalVQE revision
`f53063c9eb2a85f96479867d1dd911dc3bf6319b`, checks ggml revision
`c044a8eeae2591faa0950c8b5e514cbc4bbfc4ca`, verifies the model SHA-256, builds
arm64 and x86_64 slices with machine-native optimization disabled, and rejects
non-system dylib dependencies. Before compilation it compares all tracked and
staged source changes against HEAD and accepts only the two pinned patch
digests. `make app` embeds and signs the dylib before it signs the containing
app. The model is verified again when it is loaded.

Derived audio and provider response caches live in a separate session folder
whose name includes the processor revision and source identity. Raw provider
responses cannot be reused for cleaned input. Derived audio is removed after
recognition while the provider response cache remains. Reads, conversion,
native loading, processing and writes fail explicitly; partial derived files
are removed and original recordings remain untouched.

After strong audio processing, the text filter removes only residual exact
overlapping phrases. Disabling offline processing keeps the previous text
filter. AssemblyAI segments are also constrained to the actual audio duration:
overlapping boundary segments are clipped and segments entirely outside the
file are discarded.

Evaluation on real recordings is kept under ignored `.build` directories. In a
controlled whole-stream C-API prototype across nine full recordings, matched
duplicate words after filtering fell from 340 to 16 with AssemblyAI and from
532 to 39 with Parakeet. Source hashes, output durations and system-track
identity passed in all nine runs. The combined 4 h 44 min 43 s of audio
processed in 27 min 58 s, about 10.18x real time under concurrent load. Known
local requests remained recognizable overall. These are regression indicators
rather than a claim of perfect recognition: quiet speech and individual words
still vary between ASR runs, and the source recording remains the reference for
disputed passages.

The nine-recording prototype did not exercise Amanu's AVFoundation decoder,
old per-track AAC extraction, new direct-CAF per-track input and final stereo
AAC path together. End-to-end native validation on three representative
recordings covers those production paths and remains outside the prototype
figures above. With processor revision v3, matched duplicate words after the
actual old/new text filters fell from 154 to 17 with AssemblyAI and from 194 to
33 with Parakeet. All three original-file hashes and decoded frame counts
were verified. Version v2 failed the long recording with a playback-route
change because lazy model initialization skipped leading reference silence;
v3's complete input history repaired that measured regression.

An independent Zoom-audio proxy gives the same aggregate direction but also
shows the preservation limit. In the whole-stream C-API experiment, own-side
proxy WER changed from 41.15% to 33.43% for Parakeet and from 33.29% to 25.73%
for AssemblyAI; all-speech proxy WER changed from 28.63% to 26.22% and from
21.96% to 21.26% respectively. Deletions increased, three recordings regressed
on all-speech scoring, and cleaned AssemblyAI lost a genuine local answer that
the old path retained. These proxy numbers are not native-product accuracy
guarantees; the lost answer remains an explicit anchor in native validation.

The production codec path can be exercised on a private stereo archive without
touching session metadata or ASR by setting `AMANU_ECHO_EVAL_INPUT` and an
`AMANU_ECHO_EVAL_OUTPUT` directory inside this checkout's `.build`, then running
`swift test --skip-build --filter OfflineEchoEvaluation`. It writes the old
per-track `raw-mic.m4a` and `raw-system.m4a` extraction path, cleaned PCM tracks,
the new stereo `processed.m4a`, and a verification manifest into a unique output
subfolder.
