# Amanu 0.4.20

## Sonoma compatibility

- Lowered the minimum system requirement from macOS 15 to macOS 14.2, including the main executable and the bundled echo-suppression library.
- Added a release check that inspects every embedded Mach-O slice and nested bundle, preventing dependencies from silently raising the minimum macOS version again.
- macOS 14.2 is the oldest system with the Core Audio process-tap API Amanu needs to record the other side of a meeting. Automatic per-process detection is limited before macOS 14.4; recordings can still be started manually.

## Compatibility

- Universal binary for Apple Silicon and Intel. Local transcription requires Apple Silicon; Intel requires a cloud transcription key and has not been tested on physical hardware.
- The macOS 14.2 deployment target is verified by compilation and release-artifact inspection. Runtime testing on physical macOS 14 hardware is still pending.
