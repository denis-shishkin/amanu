# Amanu 0.4.21

## The right interface language

- Amanu now follows the Mac's primary interface language. A Mac set to Russian opens Amanu in Russian; every other language falls back to English instead of picking Russian from farther down the preferred-language list.
- An explicitly selected English or Russian interface still overrides the Mac and takes effect after Amanu restarts.

## The full-size feather promised in 0.4.20

- The macOS 26 Dock icon now uses the large hollow feather shown in the original preview.
- Icon Composer no longer shrinks or fills the feather: the layer is rasterized as a transparent outline and scaled to compensate for the system safe area.

## Compatibility

- Universal binary for Apple Silicon and Intel Macs running macOS 14.2 or later. Local transcription requires Apple Silicon; Intel requires a cloud transcription key and has not been tested on physical hardware.
