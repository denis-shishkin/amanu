# Amanu 0.4.26

## Transcription

- Transcription no longer gets stuck after acoustic echo cancellation on macOS Tahoe. Amanu now lets Core Audio choose an AAC bitrate supported by the resulting 16 kHz tracks.
- Live transcription hides an echoed microphone phrase even when the cleaner call audio was split into several blocks or arrived through the decoder with a different delay.

## Automatic recording

- Calls in DION now start automatic recording. Amanu recognises both the main DION app and its helper processes.

## Compatibility

- Universal binary for Apple Silicon and Intel Macs running macOS 14.2 or later. Local transcription requires Apple Silicon; Intel requires a cloud transcription key and has not been tested on physical hardware.
