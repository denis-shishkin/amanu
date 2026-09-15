# Amanu 0.4.23

## Local transcription

- Whisper large-v3-turbo and GigaAM v3 can now be downloaded and used directly in Amanu alongside Parakeet.
- Model downloads show progress and the exact disk space used by both Whisper and GigaAM. GigaAM is tuned for Russian speech.
- A failed recording can be transcribed again from the recordings list, with a choice of available transcription engines.

## Import existing recordings

- Drop audio or video files onto the recordings window, or choose Import from the File menu or menu bar.
- Imports show queue and transcription progress, can be cancelled, and appear alongside recordings when complete.

## Summaries

- Ollama and custom OpenAI-compatible endpoints can now generate summaries without sending recordings to Amanu's default provider.
- Advanced settings include an editable summary template, prefilled with Amanu's default instructions.

## Live transcript

- A lightweight echo filter reduces duplicated You/Them lines when recording without headphones.

## Compatibility

- Universal binary for Apple Silicon and Intel Macs running macOS 14.2 or later. Local transcription requires Apple Silicon; Intel requires a cloud transcription key and has not been tested on physical hardware.
