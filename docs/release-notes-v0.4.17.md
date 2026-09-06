# Amanu 0.4.17

This release removes acoustic echo after a meeting without changing the live
call or the saved recording.

## What changed

- Amanu now cleans a temporary microphone copy with LocalVQE before
  transcription. The original microphone and system tracks remain untouched,
  so disputed passages can still be checked against the source recording.
  Processing never opens an output device, changes playback volume or reduces
  what you hear during the call.
- The model removes playback captured by the microphone without applying noise
  gating, denoising or automatic gain control. It continues cancellation for
  one second after playback stops to cover a delayed acoustic tail. During
  sustained reference silence, Amanu uses the original microphone samples
  exactly. Large or abrupt changes in playback delay can still leave some echo.
- A controlled prototype evaluation covered nine complete recordings. Matched
  duplicate words remaining after filtering fell from 340 to 16 with
  AssemblyAI and from 532 to 39 with Parakeet. Source hashes, durations and the
  system track remained unchanged in all nine runs. Some quiet words still
  changed or disappeared, so these results do not imply perfect transcription.
- Three complete recordings also passed through the actual application paths.
  Matched duplicate words fell from 154 to 17 with AssemblyAI and from 194 to
  33 with Parakeet. Original-file hashes and decoded track lengths matched.
  These results cover the production decoder and codecs and are separate
  from the nine-recording prototype figures above.
- Provider utterances entirely beyond the real audio duration are now
  discarded, while a genuine utterance crossing the boundary is clipped.
  Cleaned audio uses a processor-specific cache and is removed after
  transcription. Processing failures leave the source recording intact.

The bundled LocalVQE model and universal library are pinned, SHA-verified and
signed inside the application. The library supports Apple Silicon and Intel.
Local Parakeet transcription still requires Apple Silicon; Intel uses a cloud
provider. Physical Intel hardware and macOS 15 have not been tested.
